import Foundation
import LoggingKit

public struct TrackRemuxer: Sendable {
    private let toolRegistry: ToolRegistry
    private let inspector: MediaInspector

    public init(toolRegistry: ToolRegistry = .shared, inspector: MediaInspector = MediaInspector()) {
        self.toolRegistry = toolRegistry
        self.inspector = inspector
    }

    // MARK: - Clear Subtitle Default Flags

    public func clearSubtitleDefaults(fileURL: URL) async throws {
        guard let mkvpropedit = toolRegistry.mkvpropedit else {
            throw ProcessError.executableNotFound("mkvpropedit")
        }

        let tracks = try await inspector.getMKVTracks(fileURL: fileURL)
        let subTracks = tracks.filter { $0.isSubtitle }
        guard !subTracks.isEmpty else { return }

        var args = [fileURL.path]
        for i in 1...subTracks.count {
            args.append(contentsOf: [
                "--edit", "track:s\(i)",
                "--set", "flag-default=0",
                "--set", "flag-forced=0"
            ])
        }

        let res = try await ProcessRunner.run(executable: mkvpropedit, arguments: args)
        if res.isSuccess {
            AppLogger.info("Cleared default flag from \(subTracks.count) embedded subtitle track(s).")
        }
    }

    // MARK: - Strip Tracks & Embed Subtitle

    /// Remux MKV keeping English audio and English subtitles, dropping foreign tracks,
    /// and optionally embedding a new SRT track.
    ///
    /// Optimization: Uses a private temporary directory outside the watch directory so the
    /// batch scanner never mistakes the intermediate file for a newly arrived video.
    public func stripTracks(fileURL: URL, srtURL: URL? = nil) async throws {
        guard let mkvmerge = toolRegistry.mkvmerge else {
            throw ProcessError.executableNotFound("mkvmerge")
        }

        let tracks = try await inspector.getMKVTracks(fileURL: fileURL)
        let audioTracks = tracks.filter { $0.isAudio }
        let subTracks = tracks.filter { $0.isSubtitle }

        let engAudio = audioTracks.filter { $0.isEnglishAudio }
        let keepAudio = engAudio.isEmpty ? audioTracks : engAudio
        let keepAudioIds = keepAudio.map { String($0.id) }

        let keepSubs = subTracks.filter { $0.isEnglishSubtitle }
        let keepSubIds = keepSubs.map { String($0.id) }

        let removedAudio = audioTracks.count - keepAudio.count
        let removedSubs = subTracks.count - keepSubs.count

        AppLogger.info("Keeping \(keepAudio.count) English audio track(s), removing \(removedAudio), removing \(removedSubs) embedded subtitle(s) (keeping \(keepSubs.count)).")

        let needsRemux = (removedAudio > 0) || (removedSubs > 0) || (srtURL != nil)
        if !needsRemux {
            AppLogger.info("Nothing to strip.")
            return
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Use .tmp extension in temp folder, completely separate from watch directory
        let tmpOut = tmpDir.appendingPathComponent("remuxed_\(fileURL.lastPathComponent)")

        var cmd = [
            "-o", tmpOut.path,
            "--audio-tracks", keepAudioIds.joined(separator: ",")
        ]

        if !keepSubIds.isEmpty {
            cmd.append(contentsOf: ["--subtitle-tracks", keepSubIds.joined(separator: ",")])
        } else {
            cmd.append("--no-subtitles")
        }

        cmd.append(fileURL.path)

        if let srt = srtURL {
            cmd.append(contentsOf: ["--language", "0:eng", srt.path])
        }

        let res = try await ProcessRunner.run(executable: mkvmerge, arguments: cmd, timeout: 600)
        guard res.isSuccess || res.exitCode == 1 else {
            AppLogger.warning("mkvmerge strip failed: \(res.stderr.suffix(300))")
            return
        }

        guard FileManager.default.fileExists(atPath: tmpOut.path) else {
            AppLogger.warning("mkvmerge produced no output file — source preserved.")
            return
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: tmpOut.path)[.size] as? Int64) ?? 0
        guard size > 0 else {
            AppLogger.warning("mkvmerge produced zero-byte output file — source preserved.")
            return
        }

        // Atomically replace original MKV
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tmpOut, to: fileURL)

        AppLogger.info("Track strip complete\(srtURL != nil ? " (SRT embedded)" : "").")
    }

    // MARK: - Normalize Embedded Subtitles

    public func normalizeEmbeddedSubtitles(fileURL: URL) async throws -> Bool {
        guard let mkvmerge = toolRegistry.mkvmerge,
              let mkvextract = toolRegistry.mkvextract else {
            return false
        }

        let tracks = try await inspector.getMKVTracks(fileURL: fileURL)
        let engSubRip = tracks.filter { $0.isEnglishSubtitle && $0.isSubRip }
        guard !engSubRip.isEmpty else { return false }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var rewritten: [(trackId: Int, data: Data)] = []

        for t in engSubRip {
            let extractedFile = tmpDir.appendingPathComponent("sub_\(t.id).srt")
            let extRes = try await ProcessRunner.run(
                executable: mkvextract,
                arguments: ["tracks", fileURL.path, "\(t.id):\(extractedFile.path)"]
            )
            guard extRes.isSuccess, let data = try? Data(contentsOf: extractedFile) else {
                AppLogger.warning("mkvextract failed for subtitle track \(t.id) — leaving it as-is.")
                continue
            }

            let normalized = SubtitleProcessor.normalizeSubtitleCase(data: data)
            if normalized != data {
                rewritten.append((trackId: t.id, data: normalized))
            }
        }

        guard !rewritten.isEmpty else { return false }

        AppLogger.info("Embedded ALL-CAPS SubRip found — converting \(rewritten.count) track(s) to sentence case.")

        var normFiles: [URL] = []
        for (i, item) in rewritten.enumerated() {
            let p = tmpDir.appendingPathComponent("normalized_\(i).srt")
            try item.data.write(to: p)
            normFiles.append(p)
        }

        let audioTracks = tracks.filter { $0.isAudio }
        let subTracks = tracks.filter { $0.isSubtitle }

        let engAudio = audioTracks.filter { $0.isEnglishAudio }
        let keepAudio = engAudio.isEmpty ? audioTracks : engAudio
        let keepAudioIds = keepAudio.map { String($0.id) }

        let replaceIds = Set(rewritten.map { $0.trackId })
        let keepSubIds = subTracks
            .filter { $0.isEnglishSubtitle && !replaceIds.contains($0.id) }
            .map { String($0.id) }

        let tmpOut = tmpDir.appendingPathComponent("norm_remuxed.mkv")
        var cmd = [
            "-o", tmpOut.path,
            "--audio-tracks", keepAudioIds.joined(separator: ",")
        ]

        if !keepSubIds.isEmpty {
            cmd.append(contentsOf: ["--subtitle-tracks", keepSubIds.joined(separator: ",")])
        } else {
            cmd.append("--no-subtitles")
        }

        cmd.append(fileURL.path)
        for p in normFiles {
            cmd.append(contentsOf: ["--language", "0:eng", p.path])
        }

        let res = try await ProcessRunner.run(executable: mkvmerge, arguments: cmd, timeout: 600)
        guard res.isSuccess || res.exitCode == 1,
              FileManager.default.fileExists(atPath: tmpOut.path) else {
            AppLogger.warning("mkvmerge subtitle normalization failed — leaving embedded subtitles as-is.")
            return false
        }

        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tmpOut, to: fileURL)

        AppLogger.info("Embedded ALL-CAPS SubRip normalized to sentence case.")
        return true
    }
}
