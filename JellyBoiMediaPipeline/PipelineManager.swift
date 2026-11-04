import Foundation
import SwiftUI
import Observation
import BaseColors
import LoggingKit

public enum ItemStatus: String, Sendable {
    case queued = "Queued"
    case running = "Processing"
    case awaitingTitle = "Needs Title"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"

    public var color: Color {
        switch self {
        case .queued: return .secondary
        case .running: return .blue
        case .awaitingTitle: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

extension JellyfinUploadStatus {
    public var color: Color {
        switch self {
        case .queued: return .secondary
        case .uploading: return Color.accentColor
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    public var systemImageName: String {
        switch self {
        case .queued: return "clock"
        case .uploading: return "arrow.up.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
}

public struct QueueItem: Identifiable, Sendable {
    public let id: UUID
    public var fileURL: URL
    public var initialSizeBytes: Int64
    public var finalSizeBytes: Int64?
    public var stage: PipelineStage = .queued
    public var status: ItemStatus = .queued
    public var progressFraction: Double = 0.0
    public var statusDetail: String = "Queued"
    public var errorMessage: String? = nil
    public var completedURL: URL? = nil

    public init(id: UUID = UUID(), fileURL: URL) {
        self.id = id
        self.fileURL = fileURL
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        self.initialSizeBytes = size
        self.finalSizeBytes = nil
    }

    public var fileName: String {
        completedURL?.lastPathComponent ?? fileURL.lastPathComponent
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useGB, .useMB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: bytes)
    }

    public var fileSizeString: String {
        let activeFinalSize: Int64? = {
            if let f = finalSizeBytes, f > 0 { return f }
            if let completed = completedURL,
               let attrs = try? FileManager.default.attributesOfItem(atPath: completed.path),
               let size = attrs[.size] as? Int64, size > 0 {
                return size
            }
            return nil
        }()

        if let finalSize = activeFinalSize {
            if initialSizeBytes > 0 && initialSizeBytes != finalSize {
                let diff = initialSizeBytes - finalSize
                let percent = Int(round(Double(diff) / Double(initialSizeBytes) * 100))
                if percent > 0 {
                    return "\(QueueItem.formatBytes(initialSizeBytes)) → \(QueueItem.formatBytes(finalSize)) (-\(percent)%)"
                } else {
                    return "\(QueueItem.formatBytes(initialSizeBytes)) → \(QueueItem.formatBytes(finalSize))"
                }
            } else {
                return QueueItem.formatBytes(finalSize)
            }
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64, size > 0 {
            return QueueItem.formatBytes(size)
        }

        if initialSizeBytes > 0 {
            return QueueItem.formatBytes(initialSizeBytes)
        }

        return "Unknown"
    }
}

public struct AppLogMessage: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public var levelColor: Color {
        level.badgeColor
    }
}

@Observable
@MainActor
public final class PipelineManager: PipelineDelegate {
    // Remuxing Pipeline Queue
    public var queue: [QueueItem] = []
    public var logs: [AppLogMessage] = []
    public var isProcessing: Bool = false
    public var currentItem: QueueItem? = nil

    // Direct to Jellyfin Server Queue
    public var jellyfinQueue: [JellyfinUploadItem] = []
    public var isJellyfinUploading: Bool = false
    public var currentJellyfinItem: JellyfinUploadItem? = nil
    private var jellyfinUploadTask: Task<Void, Never>? = nil

    // Jellyfin server / plugin detection state shared across the app
    public var jellyfinDetectionState: JellyfinDetectionState = .idle
    public var jellyfinDetectedServerURL: String = ""

    /// The Direct to Jellyfin tab is only available when a server URL is configured
    /// and the server has been verified to run the Jellyfin upload plugin.
    public var jellyfinDirectAvailable: Bool {
        let url = config.jellyfinServerURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, url == jellyfinDetectedServerURL else { return false }
        if case .detected = jellyfinDetectionState { return true }
        return false
    }

    public var config: PipelineConfig = .load()
    public var toolRegistry: ToolRegistry = .shared

    private var currentTask: Task<Void, Never>? = nil

    public init() {
        // Register logger callback with LoggingKit
        Notifier.handler = AppUserNotificationHandler.shared
        AppLogger.logHandler = { [weak self] level, msg in
            Task { @MainActor [weak self] in
                self?.appendLog(level: level, message: msg)
            }
        }
        Task {
            _ = await AppUserNotificationHandler.shared.requestAuthorization()
        }

        restoreCachedJellyfinDetection()
    }

    public func appendLog(level: LogLevel, message: String) {
        logs.append(AppLogMessage(timestamp: Date(), level: level, message: message))
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }

    // MARK: - Remuxing Queue Management

    public func addFiles(urls: [URL]) {
        withAnimation(.smooth(duration: 0.25)) {
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        addDirectory(url: url)
                    } else if url.pathExtension.lowercased() == "mkv" {
                        if !queue.contains(where: { $0.fileURL.path == url.path }) {
                            queue.append(QueueItem(fileURL: url))
                        }
                    }
                }
            }
        }
        AppLogger.info("Queue updated with \(urls.count) target(s)", tag: "Queue")
    }

    public func addDirectory(url: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        var found: [URL] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if fileURL.pathExtension.lowercased() == "mkv" &&
               !name.hasPrefix(".") &&
               !name.contains(".tmp.") &&
               !name.contains(".stripping.") {
                found.append(fileURL)
            }
        }

        found.sort { $0.lastPathComponent < $1.lastPathComponent }
        withAnimation(.smooth(duration: 0.25)) {
            for file in found {
                if !queue.contains(where: { $0.fileURL.path == file.path }) {
                    queue.append(QueueItem(fileURL: file))
                }
            }
        }
        AppLogger.info("Discovered \(found.count) MKV file(s) in \(url.lastPathComponent)", tag: "Queue")
    }

    public func removeItem(id: UUID) {
        withAnimation(.smooth(duration: 0.2)) {
            queue.removeAll { $0.id == id }
        }
    }

    public func clearCompleted() {
        withAnimation(.smooth(duration: 0.2)) {
            queue.removeAll { $0.status == .completed }
        }
    }

    // MARK: - Unified Queue Updates

    /// Applies optional field changes to a remux queue item in one place.
    /// Passing `nil` leaves a field unchanged.
    public func updateQueueItem(
        id: UUID,
        status: ItemStatus? = nil,
        stage: PipelineStage? = nil,
        progress: Double? = nil,
        detail: String? = nil,
        error: String? = nil,
        completedURL: URL? = nil,
        finalSize: Int64? = nil,
        animated: Bool = true
    ) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }

        let apply = {
            var item = self.queue[idx]
            if let status { item.status = status }
            if let stage { item.stage = stage }
            if let progress { item.progressFraction = min(max(progress, 0), 1) }
            if let detail { item.statusDetail = detail }
            if let error { item.errorMessage = error }
            if let completedURL { item.completedURL = completedURL }
            if let finalSize { item.finalSizeBytes = finalSize }
            self.queue[idx] = item
        }

        if animated {
            withAnimation(.smooth(duration: 0.3), apply)
        } else {
            apply()
        }

        if currentItem?.id == id {
            currentItem = queue[idx]
        }
    }

    /// Applies optional field changes to a Direct to Jellyfin queue item in one place.
    /// Passing `nil` leaves a field unchanged.
    public func updateJellyfinItem(
        id: UUID,
        status: JellyfinUploadStatus? = nil,
        progress: Double? = nil,
        detail: String? = nil,
        error: String? = nil,
        clearError: Bool = false,
        animated: Bool = true
    ) {
        guard let idx = jellyfinQueue.firstIndex(where: { $0.id == id }) else { return }

        let apply = {
            var item = self.jellyfinQueue[idx]
            if let status { item.status = status }
            if let progress { item.progressFraction = min(max(progress, 0), 1) }
            if let detail { item.statusDetail = detail }
            if let error { item.errorMessage = error }
            if clearError { item.errorMessage = nil }
            self.jellyfinQueue[idx] = item
        }

        if animated {
            withAnimation(.smooth(duration: 0.3), apply)
        } else {
            apply()
        }

        if currentJellyfinItem?.id == id {
            currentJellyfinItem = jellyfinQueue[idx]
        }
    }

    // MARK: - Direct to Jellyfin Queue Management

    public func addJellyfinFiles(urls: [URL]) {
        withAnimation(.smooth(duration: 0.25)) {
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        addJellyfinDirectory(url: url)
                    } else if isSupportedVideo(url: url) {
                        addJellyfinItem(url: url)
                    }
                }
            }
        }
        AppLogger.info("Direct to Jellyfin queue updated with \(urls.count) target(s)", tag: "Jellyfin")
    }

    public func addJellyfinDirectory(url: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        var found: [URL] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if isSupportedVideo(url: fileURL) && !name.hasPrefix(".") && !name.contains(".tmp.") {
                found.append(fileURL)
            }
        }

        found.sort { $0.lastPathComponent < $1.lastPathComponent }
        withAnimation(.smooth(duration: 0.25)) {
            for file in found {
                addJellyfinItem(url: file)
            }
        }
        AppLogger.info("Discovered \(found.count) media file(s) for Jellyfin direct upload", tag: "Jellyfin")
    }

    private func isSupportedVideo(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mkv", "mp4", "m4v", "mov", "avi"].contains(ext)
    }

    private func addJellyfinItem(url: URL) {
        guard !jellyfinQueue.contains(where: { $0.fileURL.path == url.path }) else { return }

        let stem = url.deletingPathExtension().lastPathComponent
        let tvRegex = try? NSRegularExpression(pattern: #"(?i)S(\d{1,2})E(\d{1,2})"#, options: [])

        if let match = tvRegex?.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
           let r1 = Range(match.range(at: 1), in: stem),
           let r2 = Range(match.range(at: 2), in: stem),
           let matchRange = Range(match.range, in: stem) {

            let season = Int(stem[r1]) ?? 1
            let episode = Int(stem[r2]) ?? 1
            let seriesRaw = String(stem[..<matchRange.lowerBound])
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ".", with: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -"))

            let remainder = String(stem[matchRange.upperBound...])
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ".", with: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -"))

            let epTitle = remainder.isEmpty ? "Episode \(episode)" : remainder

            let item = JellyfinUploadItem(
                fileURL: url,
                mediaType: .tvEpisode,
                title: seriesRaw.isEmpty ? stem : seriesRaw,
                year: nil,
                imdbId: nil,
                season: season,
                episode: episode,
                episodeTitle: epTitle,
                targetLibraryId: config.jellyfinTvLibraryId.isEmpty ? nil : config.jellyfinTvLibraryId,
                targetServerPath: config.jellyfinTvServerPath.isEmpty ? nil : config.jellyfinTvServerPath
            )
            withAnimation(.smooth(duration: 0.25)) {
                jellyfinQueue.append(item)
            }
        } else {
            let sanitized = TitleSanitizer.sanitize(rawTitle: stem)
            let yearStr = sanitized.year != nil ? String(sanitized.year!) : nil
            let item = JellyfinUploadItem(
                fileURL: url,
                mediaType: .movie,
                title: sanitized.title.isEmpty ? stem : sanitized.title,
                year: yearStr,
                imdbId: nil,
                targetLibraryId: config.jellyfinMovieLibraryId.isEmpty ? nil : config.jellyfinMovieLibraryId,
                targetServerPath: config.jellyfinMovieServerPath.isEmpty ? nil : config.jellyfinMovieServerPath
            )
            withAnimation(.smooth(duration: 0.25)) {
                jellyfinQueue.append(item)
            }
        }
    }

    public func sendToJellyfin(queueItem: QueueItem) {
        let dest = queueItem.completedURL ?? queueItem.fileURL
        addJellyfinFiles(urls: [dest])
        AppLogger.info("Sent completed remux '\(queueItem.fileName)' to Direct to Jellyfin queue", tag: "Jellyfin")
    }

    public func removeJellyfinItem(id: UUID) {
        withAnimation(.smooth(duration: 0.2)) {
            jellyfinQueue.removeAll { $0.id == id }
        }
    }

    public func clearCompletedJellyfin() {
        withAnimation(.smooth(duration: 0.2)) {
            jellyfinQueue.removeAll { $0.status == .completed }
        }
    }

    public func startJellyfinUploads() {
        guard !isJellyfinUploading else { return }
        guard !config.jellyfinServerURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendLog(level: .error, message: "Jellyfin server URL is not configured in Settings.")
            AppLogger.error("Cannot start Jellyfin upload: Server URL not set", tag: "Jellyfin")
            return
        }
        guard !config.jellyfinApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLog(level: .error, message: "Jellyfin API key is not configured in Settings.")
            AppLogger.error("Cannot start Jellyfin upload: API key not set", tag: "Jellyfin")
            return
        }

        isJellyfinUploading = true
        AppLogger.info("Jellyfin direct upload queue started", tag: "Jellyfin")

        jellyfinUploadTask = Task {
            let client = JellyfinClient()
            SleepAssertionManager.shared.acquire(reason: "JellyBoiMediaPipeline: Direct Jellyfin Upload Queue Active")
            defer {
                SleepAssertionManager.shared.release()
            }

            while let nextIndex = self.jellyfinQueue.firstIndex(where: { $0.status == .queued }) {
                if Task.isCancelled { break }

                let item = self.jellyfinQueue[nextIndex]
                self.updateJellyfinItem(
                    id: item.id,
                    status: .uploading,
                    progress: 0.0,
                    detail: "Checking upload progress on server…",
                    clearError: true
                )
                self.currentJellyfinItem = self.jellyfinQueue.first(where: { $0.id == item.id })

                AppLogger.info("Directly uploading '\(item.fileName)' to Jellyfin server (\(self.config.jellyfinServerURL))", tag: "Jellyfin")

                let uploadProgress: @Sendable (Double, String) -> Void = { [weak self] fraction, detail in
                    Task { @MainActor in
                        self?.updateJellyfinItem(
                            id: item.id,
                            progress: fraction,
                            detail: detail
                        )
                    }
                }

                do {
                    if item.mediaType == .movie {
                        self.updateJellyfinItem(id: item.id, detail: "Streaming movie to server…")
                        AppLogger.info("Uploading movie: \(item.title) (\(item.year ?? "unknown year")) as \(item.fileName)", tag: "Jellyfin")
                        try await client.uploadMovie(
                            fileURL: item.fileURL,
                            title: item.title,
                            year: item.year ?? "",
                            imdbId: item.imdbId ?? "",
                            libraryId: item.targetLibraryId ?? (self.config.jellyfinMovieLibraryId.isEmpty ? nil : self.config.jellyfinMovieLibraryId),
                            serverPath: item.targetServerPath ?? (self.config.jellyfinMovieServerPath.isEmpty ? nil : self.config.jellyfinMovieServerPath),
                            serverURL: self.config.jellyfinServerURL,
                            apiKey: self.config.jellyfinApiKey,
                            statusHandler: uploadProgress
                        )
                    } else {
                        self.updateJellyfinItem(id: item.id, detail: "Streaming episode to server…")
                        AppLogger.info("Uploading episode: \(item.title) S\(item.season ?? 0)E\(item.episode ?? 0) as \(item.fileName)", tag: "Jellyfin")
                        try await client.uploadEpisode(
                            fileURL: item.fileURL,
                            seriesTitle: item.title,
                            seriesYear: item.year ?? "",
                            seriesImdbId: item.imdbId ?? "",
                            season: item.season ?? 1,
                            episode: item.episode ?? 1,
                            episodeTitle: item.episodeTitle ?? "Episode \(item.episode ?? 1)",
                            libraryId: item.targetLibraryId ?? (self.config.jellyfinTvLibraryId.isEmpty ? nil : self.config.jellyfinTvLibraryId),
                            serverPath: item.targetServerPath ?? (self.config.jellyfinTvServerPath.isEmpty ? nil : self.config.jellyfinTvServerPath),
                            serverURL: self.config.jellyfinServerURL,
                            apiKey: self.config.jellyfinApiKey,
                            statusHandler: uploadProgress
                        )
                    }

                    // A task that was cancelled mid-upload (user hit Stop) must never be
                    // reported as completed, even if the transfer happens to return.
                    if !Task.isCancelled, self.jellyfinQueue.contains(where: { $0.id == item.id }) {
                        self.updateJellyfinItem(
                            id: item.id,
                            status: .completed,
                            progress: 1.0,
                            detail: "Uploaded successfully to Jellyfin"
                        )
                        AppLogger.success("Direct upload finished: \(item.fileName)", tag: "Jellyfin")
                    }
                } catch {
                    if self.jellyfinQueue.contains(where: { $0.id == item.id }) {
                        // A cancelled task (user hit Stop) should land in the cancelled state, not failed.
                        if Task.isCancelled {
                            self.updateJellyfinItem(
                                id: item.id,
                                status: .cancelled,
                                detail: "Upload stopped by user"
                            )
                            AppLogger.warning("Jellyfin upload stopped for \(item.fileName)", tag: "Jellyfin")
                        } else {
                            self.updateJellyfinItem(
                                id: item.id,
                                status: .failed,
                                detail: "Upload failed: \(error.localizedDescription)",
                                error: error.localizedDescription
                            )
                            AppLogger.error("Direct upload failed for \(item.fileName): \(error.localizedDescription)", tag: "Jellyfin")
                        }
                    }
                }

                self.currentJellyfinItem = nil
            }

            self.isJellyfinUploading = false
            self.jellyfinUploadTask = nil
            self.currentJellyfinItem = nil
            AppLogger.info("Jellyfin direct upload queue completed", tag: "Jellyfin")
        }
    }

    public func stopJellyfinUploads() {
        jellyfinUploadTask?.cancel()
        jellyfinUploadTask = nil
        SleepAssertionManager.shared.releaseAll()
        // The upload task owns the uploading state: it clears `isJellyfinUploading`
        // once it observes the cancellation and unwinds. Clearing it here as well would
        // allow a retry to start a second upload task while this one is still stopping,
        // which can race the cancelled task against the fresh upload.
        if let current = currentJellyfinItem {
            updateJellyfinItem(
                id: current.id,
                status: .cancelled,
                detail: "Upload stopped by user"
            )
        }
        currentJellyfinItem = nil
        AppLogger.warning("Jellyfin upload queue stopped by user", tag: "Jellyfin")
    }

    /// Probes the configured Jellyfin server to confirm it is reachable and has the
    /// Jellyfin upload plugin installed. Updates `jellyfinDetectionState` so the
    /// Direct to Jellyfin tab can show or hide accordingly.
    ///
    /// The definitive outcomes (plugin present or missing) are cached per server
    /// URL, so opening Settings or relaunching the app does not re-probe. Pass
    /// `force: true` (e.g. from the "Test & Detect" button) to bypass the cache.
    public func refreshJellyfinDetection(apiKey: String? = nil, force: Bool = false) async {
        let url = config.jellyfinServerURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else {
            jellyfinDetectionState = .idle
            jellyfinDetectedServerURL = ""
            clearCachedJellyfinDetection()
            return
        }

        if !force,
           jellyfinDetectedServerURL == url,
           isCachedJellyfinState(jellyfinDetectionState) {
            return
        }

        jellyfinDetectionState = .checking
        jellyfinDetectedServerURL = url

        let client = JellyfinClient()
        let status = await client.checkStatus(
            serverURL: url,
            apiKey: apiKey ?? config.jellyfinApiKey
        )

        // Ignore a stale result if the configured URL changed while probing.
        guard config.jellyfinServerURL.trimmingCharacters(in: .whitespaces) == url else { return }
        jellyfinDetectionState = status
        cacheJellyfinDetection(status, for: url)
    }

    // MARK: - Jellyfin Detection Cache

    private enum JellyfinDetectionCache {
        static let serverURL = "jellyfinCachedDetectionServerURL"
        static let kind = "jellyfinCachedDetectionKind"
        static let version = "jellyfinCachedPluginVersion"
        static let serverName = "jellyfinCachedServerName"
    }

    /// Only plugin presence/absence is stable enough to persist. Transient states
    /// like unauthorized or unreachable are re-probed on the next launch.
    private func isCachedJellyfinState(_ state: JellyfinDetectionState) -> Bool {
        switch state {
        case .detected, .pluginMissing:
            return true
        default:
            return false
        }
    }

    private func cacheJellyfinDetection(_ state: JellyfinDetectionState, for url: String) {
        let defaults = UserDefaults.standard
        switch state {
        case .detected(let version, let serverName):
            defaults.set(url, forKey: JellyfinDetectionCache.serverURL)
            defaults.set("detected", forKey: JellyfinDetectionCache.kind)
            defaults.set(version, forKey: JellyfinDetectionCache.version)
            defaults.set(serverName ?? "", forKey: JellyfinDetectionCache.serverName)
        case .pluginMissing(let serverName):
            defaults.set(url, forKey: JellyfinDetectionCache.serverURL)
            defaults.set("pluginMissing", forKey: JellyfinDetectionCache.kind)
            defaults.removeObject(forKey: JellyfinDetectionCache.version)
            defaults.set(serverName ?? "", forKey: JellyfinDetectionCache.serverName)
        default:
            clearCachedJellyfinDetection()
        }
    }

    private func restoreCachedJellyfinDetection() {
        let url = config.jellyfinServerURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }

        let defaults = UserDefaults.standard
        guard defaults.string(forKey: JellyfinDetectionCache.serverURL) == url,
              let kind = defaults.string(forKey: JellyfinDetectionCache.kind) else {
            return
        }

        let serverName = defaults.string(forKey: JellyfinDetectionCache.serverName) ?? ""
        let resolvedServerName = serverName.isEmpty ? nil : serverName

        switch kind {
        case "detected":
            let version = defaults.string(forKey: JellyfinDetectionCache.version) ?? "unknown"
            jellyfinDetectionState = .detected(version: version, serverName: resolvedServerName)
            jellyfinDetectedServerURL = url
        case "pluginMissing":
            jellyfinDetectionState = .pluginMissing(serverName: resolvedServerName)
            jellyfinDetectedServerURL = url
        default:
            break
        }
    }

    private func clearCachedJellyfinDetection() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: JellyfinDetectionCache.serverURL)
        defaults.removeObject(forKey: JellyfinDetectionCache.kind)
        defaults.removeObject(forKey: JellyfinDetectionCache.version)
        defaults.removeObject(forKey: JellyfinDetectionCache.serverName)
    }

    public func retryJellyfinItem(id: UUID) {
        guard jellyfinQueue.contains(where: { $0.id == id }) else { return }
        updateJellyfinItem(
            id: id,
            status: .queued,
            detail: "Queued for retry",
            clearError: true
        )
        if !isJellyfinUploading {
            startJellyfinUploads()
        }
    }

    /// Re-runs a stopped or failed remux queue item. When the remux already moved the
    /// file into the library (completedURL is set) the retry re-queues the file for a
    /// Direct to Jellyfin upload instead of blindly re-processing the pipeline.
    public func retryQueueItem(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        let item = queue[idx]

        // The file already made it into the library before the upload was stopped,
        // so retrying only needs to re-run the upload that was cancelled.
        if let completed = item.completedURL, FileManager.default.fileExists(atPath: completed.path) {
            sendToJellyfin(queueItem: item)
            if !isJellyfinUploading {
                startJellyfinUploads()
            }
            return
        }

        var retry = item
        retry.status = .queued
        retry.stage = .queued
        retry.progressFraction = 0.0
        retry.statusDetail = "Queued for retry"
        retry.errorMessage = nil
        queue[idx] = retry

        if currentItem?.id == id {
            currentItem = queue[idx]
        }

        AppLogger.info("Retrying queue item: \(item.fileName)", tag: "Pipeline")
        startProcessing()
    }

    // MARK: - Pipeline Execution

    public func startProcessing() {
        guard !isProcessing else { return }
        isProcessing = true
        AppLogger.info("Pipeline started processing", tag: "Pipeline")

        currentTask = Task {
            let pipeline = Pipeline(
                config: self.config,
                toolRegistry: self.toolRegistry,
                titlePromptProvider: nil
            )

            while let nextIndex = self.queue.firstIndex(where: { $0.status == .queued }) {
                if Task.isCancelled { break }

                let item = self.queue[nextIndex]
                self.updateQueueItem(id: item.id, status: .running)
                self.currentItem = self.queue.first(where: { $0.id == item.id })

                await pipeline.process(fileURL: item.fileURL, delegate: self)

                if let finishedIdx = self.queue.firstIndex(where: { $0.id == item.id }) {
                    let current = self.queue[finishedIdx]
                    if current.status == .running {
                        let targetDest = current.completedURL ?? current.fileURL
                        var finalSize: Int64? = nil
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: targetDest.path),
                           let size = attrs[.size] as? Int64 {
                            finalSize = size
                        }

                        var detail = current.statusDetail
                        if detail.hasPrefix("Remuxing") ||
                           detail.hasPrefix("Moving") ||
                           detail.isEmpty {
                            detail = "Completed"
                        }

                        self.updateQueueItem(
                            id: item.id,
                            status: .completed,
                            stage: .completed,
                            progress: 1.0,
                            detail: detail,
                            finalSize: finalSize
                        )
                    }
                }
                self.currentItem = nil
            }

            self.isProcessing = false
            self.currentItem = nil
        }
    }

    public func stopProcessing() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        if let current = currentItem {
            updateQueueItem(
                id: current.id,
                status: .cancelled,
                detail: "Stopped by user"
            )
        }
        currentItem = nil
        AppLogger.warning("Pipeline processing stopped by user", tag: "Pipeline")
    }

    // MARK: - PipelineDelegate

    public nonisolated func pipelineDidUpdateProgress(_ update: PipelineProgressUpdate) {
        Task { @MainActor in
            let matchIdx = self.queue.firstIndex(where: {
                $0.fileURL.path == update.fileURL.path ||
                $0.id == self.currentItem?.id ||
                $0.completedURL?.path == update.fileURL.path ||
                ($0.completedURL != nil && $0.completedURL?.path == update.destinationURL?.path)
            })

            guard let idx = matchIdx else { return }

            let destination = update.destinationURL
            var finalSize: Int64? = nil
            if let destination,
               let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let size = attrs[.size] as? Int64 {
                finalSize = size
            }

            let isCompleted = update.stage == .completed
            let isFailed = update.stage == .failed
            // Surface pipeline failures so the UI can drop the loading indicator and show the error state.
            let resolvedStatus: ItemStatus? = isCompleted ? .completed : (isFailed ? .failed : nil)

            self.updateQueueItem(
                id: self.queue[idx].id,
                status: resolvedStatus,
                stage: isCompleted ? .completed : update.stage,
                progress: isCompleted ? 1.0 : update.progressFraction,
                detail: update.detail,
                completedURL: destination,
                finalSize: finalSize
            )
        }
    }

    public nonisolated func pipelineDidLog(level: LogLevel, message: String) {
        Task { @MainActor in
            self.appendLog(level: level, message: message)
        }
    }
}
