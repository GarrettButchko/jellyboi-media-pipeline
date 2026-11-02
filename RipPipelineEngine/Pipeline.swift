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

    // MARK: - Write Stability Check

    public func waitForWrite(
        fileURL: URL,
        stableSeconds: Int = 15,
        pollInterval: Int = 3,
        delegate: PipelineDelegate? = nil
    ) async -> Bool {
        AppLogger.info("Waiting for write to complete: \(fileURL.lastPathComponent)")
        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .waitingForWrite,
            progressFraction: 0.05,
            detail: "Checking file size stability…"
        ))

        var prevSize: Int64 = -1
        var stableCount = 0

        while stableCount < stableSeconds {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let currentSize = attrs[.size] as? Int64 else {
                AppLogger.warning("File disappeared, aborting.")
                return false
            }

            if currentSize == prevSize {
                stableCount += pollInterval
            } else {
                stableCount = 0
            }
            prevSize = currentSize
        }

        let gigabytes = Double(prevSize) / 1_000_000_000.0
        AppLogger.info("Write complete — \(String(format: "%.1f", gigabytes)) GB")
        return true
    }

    // MARK: - Logging Unmatched Records

    private func logUnmatched(fileURL: URL) {
        let logURL = logDirectory.appendingPathComponent("unmatched.log")
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))]\t\(fileURL.path)\n"
        appendLog(entry: entry, to: logURL)
    }

    private func logUnmatchedSubs(fileURL: URL, imdbId: String, sourceType: SourceType) {
        let logURL = logDirectory.appendingPathComponent("unmatched_subs.log")
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))]\t\(fileURL.path)\t\(imdbId)\t\(sourceType.rawValue)\n"
        appendLog(entry: entry, to: logURL)
    }

    private func appendLog(entry: String, to logURL: URL) {
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

    // MARK: - Main File Processing

    public func process(
        fileURL: URL,
        outputDir: URL? = nil,
        forceSubs: Bool = false,
        delegate: PipelineDelegate? = nil
    ) async {
        var workingURL = fileURL
        var fileName = workingURL.lastPathComponent

        AppLogger.info("=== Processing: \(fileName) ===")
        Notifier.notify(title: "Rip Pipeline", message: "Processing: \(fileName)")

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .queued,
            progressFraction: 0.0,
            detail: "Queued for processing"
        ))

        guard await waitForWrite(fileURL: workingURL, delegate: delegate) else {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "File write incomplete or file disappeared"
            ))
            return
        }

        guard !config.omdbKey.isEmpty else {
            AppLogger.error("OMDb API key not configured. Set via preferences or config file.")
            Notifier.notify(title: "Rip Pipeline ⚠️", message: "OMDb API key not configured.")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "OMDb API key is missing. Configure in Preferences."
            ))
            return
        }

        // 1. Raw Disc Rip Recognition & Prompting
        let discCheck = DiscRipRecognizer.analyze(fileURL: workingURL)
        if discCheck.isDiscRip, let promptProvider = titlePromptProvider {
            AppLogger.info("Raw disc rip detected (\(discCheck.reason?.rawValue ?? "disc")): \(fileName)")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .awaitingTitle,
                progressFraction: 0.08,
                detail: discCheck.reason?.userExplanation ?? "Raw disc rip detected. Please enter accurate title."
            ))

            if let userTitle = await promptProvider.promptForTitle(
                fileURL: workingURL,
                suggestedTitle: discCheck.suggestedTitle,
                reason: discCheck.reason ?? .genericMakeMKV
            ), !userTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                let trimmedTitle = userTitle.trimmingCharacters(in: .whitespaces)
                AppLogger.info("User provided accurate title: '\(trimmedTitle)'")

                // Rename file on disk so future steps and file system accurately reflect the media
                let dir = workingURL.deletingLastPathComponent()
                let ext = workingURL.pathExtension
                let safeName = LibraryOrganizer.safeFilename(trimmedTitle) + (ext.isEmpty ? "" : ".\(ext)")
                let targetURL = dir.appendingPathComponent(safeName)

                if targetURL.path != workingURL.path && !FileManager.default.fileExists(atPath: targetURL.path) {
                    if (try? FileManager.default.moveItem(at: workingURL, to: targetURL)) != nil {
                        workingURL = targetURL
                        fileName = workingURL.lastPathComponent
                        AppLogger.info("Renamed file to: \(fileName)")
                    }
                }
            }
        }

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .detectingSource,
            progressFraction: 0.15,
            detail: "Inspecting media streams…"
        ))

        let sourceType = (try? await inspector.detectSourceType(fileURL: workingURL)) ?? .bluray
        Notifier.notify(title: "Rip Pipeline", message: fileName, subtitle: "Detected: \(sourceType.displayTitle)")

        // TV Episode detection: filename contains SxxExx
        let tvRegex = try? NSRegularExpression(pattern: #"S(\d{2})E(\d{2})"#, options: .caseInsensitive)
        let stem = workingURL.deletingPathExtension().lastPathComponent
        if let match = tvRegex?.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)) {
            await processTVEpisode(
                fileURL: fileURL,
                workingURL: workingURL,
                stem: stem,
                match: match,
                sourceType: sourceType,
                outputDir: outputDir,
                forceSubs: forceSubs,
                delegate: delegate
            )
            return
        }

        // Movie metadata extraction
        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .extractingMetadata,
            progressFraction: 0.25,
            detail: "Extracting title and format info…"
        ))

        let parsed = (try? await inspector.extractTitleAndMetadata(fileURL: workingURL)) ?? ParsedTitle(
            title: stem,
            yearHint: nil,
            durationMinutes: nil,
            isFromMetadata: false
        )

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .matchingMetadata,
            progressFraction: 0.35,
            detail: "Searching IMDb match for '\(parsed.title)'…"
        ))

        var matchedMovie = await omdbClient.resolveMovie(
            title: parsed.title,
            yearHint: parsed.yearHint,
            durationMinutes: parsed.durationMinutes,
            inspector: inspector,
            fileURL: workingURL
        )

        // If no match found, prompt user once more for an accurate title or IMDb ID
        if matchedMovie == nil, let promptProvider = titlePromptProvider {
            AppLogger.warning("No automatic IMDb match for '\(parsed.title)'. Requesting user input…")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .awaitingTitle,
                progressFraction: 0.38,
                detail: "No IMDb match found for '\(parsed.title)'. Please enter the correct title or IMDb ID."
            ))

            if let retryTitle = await promptProvider.promptForTitle(
                fileURL: workingURL,
                suggestedTitle: parsed.title,
                reason: .emptyOrGenericMetadata
            ), !retryTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                let trimmed = retryTitle.trimmingCharacters(in: .whitespaces)

                // Check if user entered an IMDb ID directly (e.g. tt1234567)
                if trimmed.lowercased().hasPrefix("tt") && trimmed.count >= 7 {
                    if let details = await omdbClient.fetchDetails(imdbId: trimmed),
                       let t = details["Title"] as? String,
                       let y = details["Year"] as? String {
                        matchedMovie = MovieMatch(
                            title: t,
                            year: y,
                            imdbId: trimmed,
                            votes: nil,
                            runtimeMinutes: nil
                        )
                    }
                } else {
                    let sanitized = TitleSanitizer.sanitize(rawTitle: trimmed)
                    let yearStr = sanitized.year != nil ? String(sanitized.year!) : nil
                    matchedMovie = await omdbClient.resolveMovie(
                        title: sanitized.title,
                        yearHint: yearStr,
                        durationMinutes: parsed.durationMinutes,
                        inspector: inspector,
                        fileURL: workingURL
                    )
                }
            }
        }

        guard let movie = matchedMovie else {
            logUnmatched(fileURL: workingURL)
            AppLogger.error("No IMDb match — logged to \(logDirectory.path)/unmatched.log")
            Notifier.notify(title: "Rip Pipeline ⚠️", message: "No IMDb match for '\(parsed.title)'")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "No IMDb match found"
            ))
            return
        }

        Notifier.notify(title: "Rip Pipeline", message: "\(movie.title) (\(movie.year))", subtitle: "Matched: \(movie.imdbId)")

        let preferExtended: Bool = {
            let cutPattern = #"extended|redux|director'?s cut|unrated|special edition"#
            let r = try? NSRegularExpression(pattern: cutPattern, options: .caseInsensitive)
            let inTitle = r?.firstMatch(in: parsed.title, range: NSRange(parsed.title.startIndex..., in: parsed.title)) != nil
            let inName = r?.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)) != nil
            return inTitle || inName
        }()

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .detectingCrop,
            progressFraction: 0.50,
            detail: "Detecting video crop and inspecting subtitle tracks…"
        ))

        // Parallel tasks: Crop detection + duration extraction + embedded subtitle scan
        let mediaURL = workingURL
        async let cropTask = try? cropDetector.detectCrop(fileURL: mediaURL)
        async let durationTask = try? inspector.getDecodedDuration(fileURL: mediaURL)
        async let hasEmbeddedSubRipTask = try? inspector.hasEnglishSubRipSubtitle(fileURL: mediaURL)
        async let videoFPSTask = try? inspector.getVideoFPS(fileURL: mediaURL)

        let hasEmbeddedSubRip = (await hasEmbeddedSubRipTask) ?? false
        let videoDuration = await durationTask
        let videoFPS = await videoFPSTask

        var srtData: Data? = nil
        var embeddedSrt = false

        if !forceSubs && hasEmbeddedSubRip {
            AppLogger.info("Embedded English SubRip subtitle found — keeping it.")
            embeddedSrt = true
        } else {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .processingSubtitles,
                progressFraction: 0.65,
                detail: "Fetching matching English subtitles…"
            ))
            srtData = await openSubtitlesClient.fetchSubtitles(
                imdbId: movie.imdbId,
                sourceType: sourceType,
                mediaType: "movie",
                preferExtended: preferExtended,
                mkvURL: workingURL,
                videoDuration: videoDuration,
                videoFPS: videoFPS,
                processor: subtitleProcessor
            )
            embeddedSrt = (srtData == nil) && hasEmbeddedSubRip
        }

        let crop = await cropTask

        // Subtitle normalization & sync
        var srtTmpURL: URL? = nil
        var normalizedEmbedded = false

        if embeddedSrt {
            normalizedEmbedded = (try? await trackRemuxer.normalizeEmbeddedSubtitles(fileURL: workingURL)) ?? false
            Notifier.notify(
                title: "Rip Pipeline",
                message: "\(movie.title) (\(movie.year))",
                subtitle: normalizedEmbedded ? "Embedded ALL-CAPS subtitles normalized" : "Embedded subtitles kept"
            )
        } else if var subData = srtData {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .processingSubtitles,
                progressFraction: 0.75,
                detail: "Cleaning ads and syncing subtitle speech…"
            ))
            subData = SubtitleProcessor.stripSubtitleAds(data: subData)
            subData = SubtitleProcessor.stripSubtitleFormatting(data: subData)
            subData = SubtitleProcessor.normalizeSubtitleCase(data: subData)
            subData = await subtitleProcessor.syncSubtitlesMovie(srtData: subData, mkvURL: workingURL)

            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pipeline_sub.srt")
            if (try? subData.write(to: tmp)) != nil {
                srtTmpURL = tmp
            }
            Notifier.notify(title: "Rip Pipeline", message: "\(movie.title) (\(movie.year))", subtitle: "Subtitles downloaded & synced")
        } else {
            logUnmatchedSubs(fileURL: workingURL, imdbId: movie.imdbId, sourceType: sourceType)
            Notifier.notify(title: "Rip Pipeline", message: "\(movie.title) (\(movie.year))", subtitle: "No subtitles found")
        }

        defer {
            if let tmp = srtTmpURL {
                try? FileManager.default.removeItem(at: tmp)
            }
        }

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .remuxingTracks,
            progressFraction: 0.85,
            detail: "Remuxing clean English audio and subtitle tracks…"
        ))

        try? await trackRemuxer.stripTracks(fileURL: workingURL, srtURL: srtTmpURL)
        try? await trackRemuxer.clearSubtitleDefaults(fileURL: workingURL)
        Notifier.notify(title: "Rip Pipeline", message: "\(movie.title) (\(movie.year))", subtitle: "Tracks remuxed")

        if let validCrop = crop {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .applyingCrop,
                progressFraction: 0.90,
                detail: "Writing crop metadata into MKV header…"
            ))
            try? await cropDetector.applyCrop(fileURL: workingURL, crop: validCrop)
            Notifier.notify(title: "Rip Pipeline", message: "\(movie.title) (\(movie.year))", subtitle: "Crop metadata applied")
        }

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .movingToLibrary,
            progressFraction: 0.95,
            detail: "Moving to organized library…"
        ))

        let libraryDir = outputDir ?? config.libraryDir
        guard let dest = try? LibraryOrganizer.moveToLibrary(
            srcURL: workingURL,
            title: movie.title,
            year: movie.year,
            imdbId: movie.imdbId,
            libraryDir: libraryDir
        ) else {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "Failed to move file to destination library"
            ))
            return
        }

        let subStatus = normalizedEmbedded ? "embedded subtitles normalized" :
            (embeddedSrt ? "embedded subtitles kept" :
            (srtData != nil ? "with subtitles (embedded)" : "no subtitles"))

        let destSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useGB, .useMB]
        bcf.countStyle = .file
        let sizeStr = bcf.string(fromByteCount: destSize)

        // Direct Jellyfin Server Upload (if enabled and configured)
        if config.jellyfinUploadEnabled && !config.jellyfinServerURL.trimmingCharacters(in: .whitespaces).isEmpty {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                destinationURL: dest,
                stage: .uploadingToJellyfin,
                progressFraction: 0.97,
                detail: "Streaming to Jellyfin server…"
            ))
            let client = JellyfinClient()
            var uploadError: Error?
            do {
                try await client.uploadMovie(
                    fileURL: dest,
                    title: movie.title,
                    year: movie.year,
                    imdbId: movie.imdbId,
                    libraryId: config.jellyfinMovieLibraryId.isEmpty ? nil : config.jellyfinMovieLibraryId,
                    serverPath: config.jellyfinMovieServerPath.isEmpty ? nil : config.jellyfinMovieServerPath,
                    serverURL: config.jellyfinServerURL,
                    apiKey: config.jellyfinApiKey
                )
                AppLogger.info("Direct Jellyfin upload completed: \(dest.lastPathComponent)")
            } catch {
                // A cancelled task means the user hit Stop during the upload — keep the
                // queue item in the cancelled state instead of treating it as a failure.
                if Task.isCancelled {
                    AppLogger.info("Jellyfin upload cancelled: \(dest.lastPathComponent)")
                    return
                }
                AppLogger.error("Jellyfin upload failed: \(error.localizedDescription)")
                uploadError = error
            }

            // Never fall through to "completed" if the upload did not actually finish.
            if let uploadError {
                await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                    fileURL: fileURL,
                    destinationURL: dest,
                    stage: .failed,
                    progressFraction: 0.97,
                    detail: "Jellyfin upload failed: \(uploadError.localizedDescription)"
                ))
                return
            }
        }

        AppLogger.info("Finished: \(dest.lastPathComponent) (\(sizeStr))")
        Notifier.notify(title: "Rip Pipeline ✓", message: "\(movie.title) (\(movie.year))", subtitle: "\(sizeStr) — \(subStatus)")

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            destinationURL: dest,
            stage: .completed,
            progressFraction: 1.0,
            detail: "Successfully processed (\(sizeStr), \(subStatus))"
        ))
    }

    // MARK: - TV Episode Processing

    public func processTVEpisode(
        fileURL: URL,
        workingURL: URL? = nil,
        stem: String,
        match: NSTextCheckingResult,
        sourceType: SourceType,
        outputDir: URL?,
        forceSubs: Bool,
        delegate: PipelineDelegate? = nil
    ) async {
        let activeURL = workingURL ?? fileURL
        guard let r1 = Range(match.range(at: 1), in: stem),
              let r2 = Range(match.range(at: 2), in: stem),
              let matchRange = Range(match.range, in: stem) else { return }

        let season = Int(stem[r1]) ?? 1
        let episode = Int(stem[r2]) ?? 1
        let seriesRaw = String(stem[..<matchRange.lowerBound])
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))

        AppLogger.info("TV episode detected: '\(seriesRaw)' S\(String(format: "%02d", season))E\(String(format: "%02d", episode))")

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .matchingMetadata,
            progressFraction: 0.35,
            detail: "Looking up series '\(seriesRaw)' on IMDb…"
        ))

        guard let series = await omdbClient.lookupSeries(title: seriesRaw) else {
            logUnmatched(fileURL: activeURL)
            AppLogger.error("No IMDb series match — logged to unmatched.log")
            Notifier.notify(title: "Rip Pipeline ⚠️", message: "No IMDb series match for '\(seriesRaw)'")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "No IMDb series match for '\(seriesRaw)'"
            ))
            return
        }

        guard let ep = await omdbClient.lookupEpisode(
            seriesTitle: series.title,
            seriesYear: series.year,
            seriesImdbId: series.imdbId,
            season: season,
            episode: episode
        ) else {
            logUnmatched(fileURL: activeURL)
            AppLogger.error("No IMDb episode match — logged to unmatched.log")
            Notifier.notify(title: "Rip Pipeline ⚠️", message: "\(series.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "No episode match for S\(season)E\(episode)"
            ))
            return
        }

        Notifier.notify(title: "Rip Pipeline", message: "\(series.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))", subtitle: "Matched: \(ep.episodeTitle)")

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .detectingCrop,
            progressFraction: 0.50,
            detail: "Detecting crop and subtitle tracks…"
        ))

        async let cropTask = try? cropDetector.detectCrop(fileURL: activeURL)
        async let durationTask = try? inspector.getDecodedDuration(fileURL: activeURL)
        async let hasEmbeddedSubRipTask = try? inspector.hasEnglishSubRipSubtitle(fileURL: activeURL)
        async let videoFPSTask = try? inspector.getVideoFPS(fileURL: activeURL)

        let hasEmbeddedSubRip = (await hasEmbeddedSubRipTask) ?? false
        let videoDuration = await durationTask
        let videoFPS = await videoFPSTask

        var srtData: Data? = nil
        var embeddedSrt = false

        if !forceSubs && hasEmbeddedSubRip {
            AppLogger.info("Embedded English SubRip subtitle found — keeping it.")
            embeddedSrt = true
        } else {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .processingSubtitles,
                progressFraction: 0.65,
                detail: "Fetching matching TV episode subtitles…"
            ))
            srtData = await openSubtitlesClient.fetchSubtitles(
                imdbId: ep.episodeImdbId,
                sourceType: sourceType,
                mediaType: "episode",
                preferExtended: false,
                mkvURL: activeURL,
                videoDuration: videoDuration,
                videoFPS: videoFPS,
                processor: subtitleProcessor
            )
            embeddedSrt = (srtData == nil) && hasEmbeddedSubRip
        }

        let crop = await cropTask

        var srtTmpURL: URL? = nil
        var normalizedEmbedded = false

        if embeddedSrt {
            normalizedEmbedded = (try? await trackRemuxer.normalizeEmbeddedSubtitles(fileURL: activeURL)) ?? false
            Notifier.notify(
                title: "Rip Pipeline",
                message: "\(series.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))",
                subtitle: normalizedEmbedded ? "Embedded ALL-CAPS subtitles normalized" : "Embedded subtitles kept"
            )
        } else if var subData = srtData {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .processingSubtitles,
                progressFraction: 0.75,
                detail: "Synchronizing TV episode subtitles (alass)…"
            ))
            subData = SubtitleProcessor.stripSubtitleAds(data: subData)
            subData = SubtitleProcessor.stripSubtitleFormatting(data: subData)
            subData = SubtitleProcessor.normalizeSubtitleCase(data: subData)
            subData = await subtitleProcessor.syncSubtitlesTV(
                srtData: subData,
                mkvURL: activeURL,
                videoDuration: videoDuration,
                sourceType: sourceType
            )

            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pipeline_sub.srt")
            if (try? subData.write(to: tmp)) != nil {
                srtTmpURL = tmp
            }
            Notifier.notify(title: "Rip Pipeline", message: "\(series.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))", subtitle: "Subtitles downloaded & synced")
        } else {
            logUnmatchedSubs(fileURL: activeURL, imdbId: ep.episodeImdbId, sourceType: sourceType)
            Notifier.notify(title: "Rip Pipeline", message: "\(series.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))", subtitle: "No subtitles found")
        }

        defer {
            if let tmp = srtTmpURL {
                try? FileManager.default.removeItem(at: tmp)
            }
        }

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .remuxingTracks,
            progressFraction: 0.85,
            detail: "Remuxing tracks…"
        ))

        try? await trackRemuxer.stripTracks(fileURL: activeURL, srtURL: srtTmpURL)
        try? await trackRemuxer.clearSubtitleDefaults(fileURL: activeURL)
        Notifier.notify(title: "Rip Pipeline", message: "\(series.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))", subtitle: "Tracks remuxed")

        if let validCrop = crop {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .applyingCrop,
                progressFraction: 0.90,
                detail: "Applying crop metadata…"
            ))
            try? await cropDetector.applyCrop(fileURL: activeURL, crop: validCrop)
            Notifier.notify(title: "Rip Pipeline", message: "\(series.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))", subtitle: "Crop metadata applied")
        }

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .movingToLibrary,
            progressFraction: 0.95,
            detail: "Moving to TV library…"
        ))

        let tvLibraryDir = outputDir ?? config.tvLibraryDir
        guard let dest = try? LibraryOrganizer.moveToTVLibrary(
            srcURL: activeURL,
            seriesTitle: series.title,
            seriesYear: series.year,
            seriesImdbId: series.imdbId,
            season: season,
            episode: episode,
            episodeTitle: ep.episodeTitle,
            tvLibraryDir: tvLibraryDir
        ) else {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "Failed to move TV episode to library"
            ))
            return
        }

        let subStatus = normalizedEmbedded ? "embedded subtitles normalized" :
            (embeddedSrt ? "embedded subtitles kept" :
            (srtData != nil ? "with subtitles (embedded)" : "no subtitles"))

        let destSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useGB, .useMB]
        bcf.countStyle = .file
        let sizeStr = bcf.string(fromByteCount: destSize)

        // Direct Jellyfin Server Upload (if enabled and configured)
        if config.jellyfinUploadEnabled && !config.jellyfinServerURL.trimmingCharacters(in: .whitespaces).isEmpty {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                destinationURL: dest,
                stage: .uploadingToJellyfin,
                progressFraction: 0.97,
                detail: "Streaming episode to Jellyfin server…"
            ))
            let client = JellyfinClient()
            var uploadError: Error?
            do {
                try await client.uploadEpisode(
                    fileURL: dest,
                    seriesTitle: series.title,
                    seriesYear: series.year,
                    seriesImdbId: series.imdbId,
                    season: season,
                    episode: episode,
                    episodeTitle: ep.episodeTitle,
                    libraryId: config.jellyfinTvLibraryId.isEmpty ? nil : config.jellyfinTvLibraryId,
                    serverPath: config.jellyfinTvServerPath.isEmpty ? nil : config.jellyfinTvServerPath,
                    serverURL: config.jellyfinServerURL,
                    apiKey: config.jellyfinApiKey
                )
                AppLogger.info("Direct Jellyfin episode upload completed: \(dest.lastPathComponent)")
            } catch {
                // A cancelled task means the user hit Stop during the upload — keep the
                // queue item in the cancelled state instead of treating it as a failure.
                if Task.isCancelled {
                    AppLogger.info("Jellyfin upload cancelled: \(dest.lastPathComponent)")
                    return
                }
                AppLogger.error("Jellyfin upload failed: \(error.localizedDescription)")
                uploadError = error
            }

            // Never fall through to "completed" if the upload did not actually finish.
            if let uploadError {
                await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                    fileURL: fileURL,
                    destinationURL: dest,
                    stage: .failed,
                    progressFraction: 0.97,
                    detail: "Jellyfin upload failed: \(uploadError.localizedDescription)"
                ))
                return
            }
        }

        AppLogger.info("Finished: \(dest.lastPathComponent) (\(sizeStr))")
        Notifier.notify(title: "Rip Pipeline ✓", message: "\(series.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))", subtitle: "\(sizeStr) — \(subStatus)")

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            destinationURL: dest,
            stage: .completed,
            progressFraction: 1.0,
            detail: "Successfully processed (\(subStatus))"
        ))
    }
}
