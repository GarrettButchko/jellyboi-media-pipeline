import Foundation
import LoggingKit

public struct Pipeline: Sendable {
    public let config: PipelineConfig
    public let toolRegistry: ToolRegistry
    public let inspector: MediaInspector
    public let omdbClient: OMDbClient
    public let openSubtitlesClient: OpenSubtitlesClient
    public let cropDetector: CropDetector
    public let subtitleProcessor: SubtitleProcessor
    public let trackRemuxer: TrackRemuxer
    public let logDirectory: URL
    public let titlePromptProvider: TitlePromptProvider?

    public init(
        config: PipelineConfig = .load(),
        toolRegistry: ToolRegistry = .shared,
        customEpisodeOverrides: [String: (title: String, imdbId: String)] = [:],
        titlePromptProvider: TitlePromptProvider? = CLITitlePromptProvider.shared
    ) {
        self.config = config
        self.toolRegistry = toolRegistry
        self.inspector = MediaInspector(toolRegistry: toolRegistry)
        self.omdbClient = OMDbClient(
            apiKey: config.omdbKey,
            customEpisodeOverrides: customEpisodeOverrides
        )
        self.openSubtitlesClient = OpenSubtitlesClient(
            apiKey: config.openSubtitlesKey,
            userAgent: config.openSubtitlesUserAgent,
            username: config.openSubtitlesUsername,
            password: config.openSubtitlesPassword
        )
        self.cropDetector = CropDetector(toolRegistry: toolRegistry, inspector: inspector)
        self.subtitleProcessor = SubtitleProcessor(toolRegistry: toolRegistry)
        self.trackRemuxer = TrackRemuxer(toolRegistry: toolRegistry, inspector: inspector)
        self.titlePromptProvider = titlePromptProvider

        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let logs = libraryDir.appendingPathComponent("Logs/RipPipeline")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        self.logDirectory = logs
    }

    // MARK: - TV Episode Pattern Helper

    public static let tvEpisodeRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(?:s(\d{1,2})[ ._-]?e(\d{1,2})|(\d{1,2})x(\d{1,2})|(?:season|series)[\s._-]*(\d{1,2})[\s._-]*(?:episode|ep)[\s._-]*(\d{1,2}))\b"#,
        options: []
    )

    public static func parseTVEpisodeInfo(from text: String) -> (seriesTitle: String, season: Int, episode: Int)? {
        guard let regex = tvEpisodeRegex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        var season = 1
        var episode = 1
        if let r1 = Range(match.range(at: 1), in: text), let r2 = Range(match.range(at: 2), in: text) {
            season = Int(text[r1]) ?? 1
            episode = Int(text[r2]) ?? 1
        } else if let r3 = Range(match.range(at: 3), in: text), let r4 = Range(match.range(at: 4), in: text) {
            season = Int(text[r3]) ?? 1
            episode = Int(text[r4]) ?? 1
        } else if let r5 = Range(match.range(at: 5), in: text), let r6 = Range(match.range(at: 6), in: text) {
            season = Int(text[r5]) ?? 1
            episode = Int(text[r6]) ?? 1
        }

        let prefix = String(text[..<matchRange.lowerBound])
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))

        return (seriesTitle: prefix, season: season, episode: episode)
    }

    // MARK: - Logging Unmatched Records

    func logUnmatched(fileURL: URL) {
        let logURL = logDirectory.appendingPathComponent("unmatched.log")
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))]\t\(fileURL.path)\n"
        appendLog(entry: entry, to: logURL)
    }

    func logUnmatchedSubs(fileURL: URL, imdbId: String, sourceType: SourceType) {
        let logURL = logDirectory.appendingPathComponent("unmatched_subs.log")
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))]\t\(fileURL.path)\t\(imdbId)\t\(sourceType.rawValue)\n"
        appendLog(entry: entry, to: logURL)
    }

    func appendLog(entry: String, to logURL: URL) {
        guard let data = entry.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logURL)
        }
    }

    // MARK: - Unified Pipeline Flow

    public func process(
        fileURL: URL,
        workingURL initialWorkingURL: URL? = nil,
        tvHint: TVEpisodeHint? = nil,
        sourceTypeHint: SourceType? = nil,
        outputDir: URL? = nil,
        forceSubs: Bool = false,
        delegate: PipelineDelegate? = nil
    ) async {
        var workingURL = initialWorkingURL ?? fileURL
        var fileName = workingURL.lastPathComponent

        // Step 1: Preparation & write stability validation
        guard await validateAndPrepare(fileURL: fileURL, workingURL: workingURL, fileName: fileName, delegate: delegate) else {
            return
        }

        // Step 2: Disc rip detection & interactive renaming
        (workingURL, fileName) = await handleRawDiscRip(
            fileURL: fileURL,
            workingURL: workingURL,
            fileName: fileName,
            delegate: delegate
        )

        // Step 3: Source media detection
        let sourceType: SourceType
        if let hint = sourceTypeHint {
            sourceType = hint
        } else {
            sourceType = await detectSourceType(
                fileURL: fileURL,
                workingURL: workingURL,
                fileName: fileName,
                delegate: delegate
            )
        }

        // Step 4: Metadata resolution (Modularized Area: Movie vs TV)
        guard let target = await resolveMediaTarget(
            fileURL: fileURL,
            workingURL: workingURL,
            tvHint: tvHint,
            delegate: delegate
        ) else {
            return
        }

        Notifier.notify(title: "Rip Pipeline", message: target.displayTitle, subtitle: target.matchedSubtitle)

        // Step 5: Parallel media inspection
        let inspection = await inspectMediaStreams(
            fileURL: fileURL,
            workingURL: workingURL,
            delegate: delegate
        )

        // Step 6: Subtitle resolution & sync (Modularized Area: Movie vs TV)
        let subResult = await resolveAndProcessSubtitles(
            target: target,
            fileURL: fileURL,
            workingURL: workingURL,
            fileName: fileName,
            sourceType: sourceType,
            inspection: inspection,
            forceSubs: forceSubs,
            delegate: delegate
        )

        defer {
            if let tmp = subResult.srtTmpURL {
                try? FileManager.default.removeItem(at: tmp)
            }
        }

        // Step 7: Remux clean tracks
        await remuxTracks(
            target: target,
            fileURL: fileURL,
            workingURL: workingURL,
            srtURL: subResult.srtTmpURL,
            delegate: delegate
        )

        // Step 8: Apply crop metadata
        await applyCropIfDetected(
            target: target,
            fileURL: fileURL,
            workingURL: workingURL,
            crop: inspection.crop,
            delegate: delegate
        )

        // Step 9: Move to destination library (Modularized Area: Movie vs TV)
        guard let dest = await moveMediaToLibrary(
            target: target,
            fileURL: fileURL,
            workingURL: workingURL,
            outputDir: outputDir,
            delegate: delegate
        ) else {
            return
        }

        // Step 10: Finalization
        await finalizePipeline(
            target: target,
            fileURL: fileURL,
            destinationURL: dest,
            subResult: subResult,
            delegate: delegate
        )
    }
}
