import Foundation
import SwiftUI
import Observation

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
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}

public struct TitlePromptRequest: Identifiable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let fileName: String
    public let suggestedTitle: String?
    public let reason: DiscRipReason

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        suggestedTitle: String?,
        reason: DiscRipReason
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.suggestedTitle = suggestedTitle
        self.reason = reason
    }
}

@Observable
@MainActor
public final class PipelineManager: PipelineDelegate, TitlePromptProvider {
    public var queue: [QueueItem] = []
    public var logs: [AppLogMessage] = []
    public var isProcessing: Bool = false
    public var currentItem: QueueItem? = nil

    // Interactive title prompt state
    public var activeTitleRequest: TitlePromptRequest? = nil
    private var activeTitleContinuation: CheckedContinuation<String?, Never>? = nil

    public var config: PipelineConfig = .load()
    public var toolRegistry: ToolRegistry = .shared

    private var currentTask: Task<Void, Never>? = nil

    public init() {
        // Register logger callback
        Logger.notificationHandler = AppUserNotificationHandler.shared
        Logger.logCallback = { [weak self] level, msg in
            Task { @MainActor [weak self] in
                self?.appendLog(level: level, message: msg)
            }
        }
        Task {
            _ = await AppUserNotificationHandler.shared.requestAuthorization()
        }
    }

    public func appendLog(level: LogLevel, message: String) {
        logs.append(AppLogMessage(timestamp: Date(), level: level, message: message))
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }

    // MARK: - Queue Management

    public func addFiles(urls: [URL]) {
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
        for file in found {
            if !queue.contains(where: { $0.fileURL.path == file.path }) {
                queue.append(QueueItem(fileURL: file))
            }
        }
    }

    public func removeItem(id: UUID) {
        queue.removeAll { $0.id == id }
    }

    public func clearCompleted() {
        queue.removeAll { $0.status == .completed }
    }

    // MARK: - Interactive Title Prompt Response

    public func submitTitle(_ title: String?) {
        activeTitleContinuation?.resume(returning: title)
        activeTitleContinuation = nil
        activeTitleRequest = nil
    }

    public func cancelPendingPrompt() {
        activeTitleContinuation?.resume(returning: nil)
        activeTitleContinuation = nil
        activeTitleRequest = nil
    }

    // MARK: - TitlePromptProvider Implementation

    public nonisolated func promptForTitle(
        fileURL: URL,
        suggestedTitle: String?,
        reason: DiscRipReason
    ) async -> String? {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.activeTitleContinuation = continuation
                self.activeTitleRequest = TitlePromptRequest(
                    fileURL: fileURL,
                    suggestedTitle: suggestedTitle,
                    reason: reason
                )
                if let idx = self.queue.firstIndex(where: { $0.fileURL.path == fileURL.path || $0.id == self.currentItem?.id }) {
                    self.queue[idx].status = .awaitingTitle
                    self.queue[idx].stage = .awaitingTitle
                    self.queue[idx].statusDetail = reason.userExplanation
                }
            }
        }
    }

    // MARK: - Pipeline Execution

    public func startProcessing() {
        guard !isProcessing else { return }
        isProcessing = true

        currentTask = Task {
            let pipeline = Pipeline(
                config: self.config,
                toolRegistry: self.toolRegistry,
                titlePromptProvider: self
            )

            while let nextIndex = self.queue.firstIndex(where: { $0.status == .queued }) {
                if Task.isCancelled { break }

                var item = self.queue[nextIndex]
                item.status = .running
                self.queue[nextIndex] = item
                self.currentItem = item

                await pipeline.process(fileURL: item.fileURL, delegate: self)

                if let finishedIdx = self.queue.firstIndex(where: { $0.id == item.id }) {
                    if self.queue[finishedIdx].status == .running || self.queue[finishedIdx].status == .awaitingTitle {
                        self.queue[finishedIdx].status = .completed
                        self.queue[finishedIdx].stage = .completed
                        self.queue[finishedIdx].progressFraction = 1.0

                        let targetDest = self.queue[finishedIdx].completedURL ?? self.queue[finishedIdx].fileURL
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: targetDest.path),
                           let size = attrs[.size] as? Int64 {
                            self.queue[finishedIdx].finalSizeBytes = size
                        }

                        if self.queue[finishedIdx].statusDetail.hasPrefix("Remuxing") ||
                           self.queue[finishedIdx].statusDetail.hasPrefix("Moving") ||
                           self.queue[finishedIdx].statusDetail.isEmpty {
                            self.queue[finishedIdx].statusDetail = "Completed"
                        }
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
        cancelPendingPrompt()
        isProcessing = false
        if let current = currentItem, let idx = queue.firstIndex(where: { $0.id == current.id }) {
            queue[idx].status = .cancelled
            queue[idx].statusDetail = "Stopped by user"
        }
        currentItem = nil
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

            self.queue[idx].stage = update.stage
            if let frac = update.progressFraction {
                self.queue[idx].progressFraction = frac
            }
            self.queue[idx].statusDetail = update.detail

            if let dest = update.destinationURL {
                self.queue[idx].completedURL = dest
                if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
                   let size = attrs[.size] as? Int64 {
                    self.queue[idx].finalSizeBytes = size
                }
            }

            if update.stage == .completed {
                self.queue[idx].status = .completed
                self.queue[idx].stage = .completed
                self.queue[idx].progressFraction = 1.0
                if let dest = update.destinationURL {
                    self.queue[idx].completedURL = dest
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
                       let size = attrs[.size] as? Int64 {
                        self.queue[idx].finalSizeBytes = size
                    }
                }
            } else if update.stage == .failed {
                self.queue[idx].status = .failed
                self.queue[idx].errorMessage = update.detail
            } else if update.stage == .awaitingTitle {
                self.queue[idx].status = .awaitingTitle
            } else {
                if self.queue[idx].status != .running {
                    self.queue[idx].status = .running
                }
            }
        }
    }

    public nonisolated func pipelineDidLog(level: LogLevel, message: String) {
        Task { @MainActor in
            self.appendLog(level: level, message: message)
        }
    }
}
