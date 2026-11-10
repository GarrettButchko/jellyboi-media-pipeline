import Foundation
import LoggingKit

extension Pipeline {
    // MARK: - TV Metadata Resolution Area

    func resolveTVMetadata(
        fileURL: URL,
        workingURL: URL,
        stem: String,
        seriesTitle: String,
        season: Int,
        episode: Int,
        delegate: PipelineDelegate?
    ) async -> PipelineMediaTarget? {
        let activeURL = workingURL
        let seriesRaw = seriesTitle
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

        var series = await omdbClient.lookupSeries(title: seriesRaw)

        // If the raw name fails, ask the on-device model for a cleaned-up series name and retry once.
        if series == nil,
           MediaQueryAssistant.isAvailable,
           let ai = await MediaQueryAssistant.suggestSearchName(forFileNamed: stem),
           !ai.searchTitle.isEmpty,
           ai.searchTitle.caseInsensitiveCompare(seriesRaw) != .orderedSame {
            AppLogger.warning("No IMDb match for '\(seriesRaw)' — retrying with on-device query '\(ai.searchTitle)'")
            series = await omdbClient.lookupSeries(title: ai.searchTitle, alternateTitles: [seriesRaw])
        }

        // Title Disambiguation: if no series match, search OMDb for closest TV series and present ranked choices
        if series == nil, config.promptForAmbiguousTitles, let promptProvider = titlePromptProvider {
            let searchTitle = seriesRaw
            let candidates = await omdbClient.search(title: searchTitle, type: "series")
            if !candidates.isEmpty {
                await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                    fileURL: fileURL,
                    stage: .awaitingTitle,
                    progressFraction: 0.38,
                    detail: "Multiple series matches found for '\(searchTitle)'. Please confirm the correct TV show."
                ))
                if let chosen = await promptProvider.promptForTitleDisambiguation(
                    fileURL: activeURL,
                    originalQuery: searchTitle,
                    candidates: candidates
                ) {
                    series = (
                        title: chosen.title,
                        year: chosen.year,
                        imdbId: chosen.imdbId
                    )
                }
            }
        }

        // If still no series match, prompt the user in a loop until matched or cancelled
        var currentSeriesPrompt = seriesRaw
        var seriesFailureDetail: String? = nil

        while series == nil, let promptProvider = titlePromptProvider {
            AppLogger.warning("No automatic IMDb match for TV series '\(currentSeriesPrompt)'. Requesting user input…")
            let promptDetail = seriesFailureDetail ?? "No IMDb TV series match found for '\(currentSeriesPrompt)'. Please enter the correct series title or IMDb ID."
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .awaitingTitle,
                progressFraction: 0.38,
                detail: promptDetail
            ))

            guard let userTitle = await promptProvider.promptForTitle(
                fileURL: activeURL,
                suggestedTitle: currentSeriesPrompt,
                candidates: [],
                reason: .emptyOrGenericMetadata
            ), !userTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
                // User cancelled or skipped
                AppLogger.info("User cancelled or skipped TV series entry.")
                break
            }

            let trimmed = userTitle.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased() == "skip" {
                AppLogger.info("User explicitly skipped TV series entry.")
                break
            }

            currentSeriesPrompt = trimmed

            // 1. Check if user entered an IMDb ID directly (e.g. tt1234567)
            if trimmed.lowercased().hasPrefix("tt") && trimmed.count >= 7 {
                if let details = await omdbClient.fetchDetails(imdbId: trimmed),
                   let t = details["Title"] as? String,
                   let y = details["Year"] as? String {
                    series = (title: t, year: y, imdbId: trimmed)
                    break
                } else {
                    seriesFailureDetail = "Could not find any IMDb entry for ID '\(trimmed)'."
                    continue
                }
            }

            // 2. If there is a model, run through the model again
            var searchTitle = trimmed
            if MediaQueryAssistant.isAvailable {
                await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                    fileURL: fileURL,
                    stage: .extractingMetadata,
                    progressFraction: 0.38,
                    detail: "Analyzing '\(trimmed)' with on-device AI…"
                ))

                if let ai = await MediaQueryAssistant.suggestSearchName(forFileNamed: trimmed), !ai.searchTitle.isEmpty {
                    searchTitle = ai.searchTitle
                }
            } else {
                let sanitized = TitleSanitizer.sanitize(rawTitle: trimmed)
                searchTitle = sanitized.title
            }

            // 3. Search OMDb for series
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .matchingMetadata,
                progressFraction: 0.39,
                detail: "Searching IMDb for series '\(searchTitle)'…"
            ))

            series = await omdbClient.lookupSeries(title: searchTitle, alternateTitles: [trimmed])

            // 4. Disambiguation if needed
            if series == nil, config.promptForAmbiguousTitles {
                let candidates = await omdbClient.search(title: searchTitle, type: "series")
                if !candidates.isEmpty {
                    await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                        fileURL: fileURL,
                        stage: .awaitingTitle,
                        progressFraction: 0.39,
                        detail: "Multiple series matches found for '\(searchTitle)'. Please confirm the correct TV show."
                    ))
                    if let chosen = await promptProvider.promptForTitleDisambiguation(
                        fileURL: activeURL,
                        originalQuery: searchTitle,
                        candidates: candidates
                    ) {
                        series = (
                            title: chosen.title,
                            year: chosen.year,
                            imdbId: chosen.imdbId
                        )
                        break
                    }
                }
            }

            if series == nil {
                seriesFailureDetail = "No IMDb series match found for '\(searchTitle)'. Please try another title or IMDb ID."
            }
        }

        guard let matchedSeries = series else {
            logUnmatched(fileURL: activeURL)
            AppLogger.error("No IMDb series match — logged to unmatched.log")
            Notifier.notify(title: "Rip Pipeline ⚠️", message: "No IMDb series match for '\(seriesRaw)'")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "No IMDb series match for '\(seriesRaw)'"
            ))
            return nil
        }

        var epMatch = await omdbClient.lookupEpisode(
            seriesTitle: matchedSeries.title,
            seriesYear: matchedSeries.year,
            seriesImdbId: matchedSeries.imdbId,
            season: season,
            episode: episode
        )

        // Fallback: If OMDb has the series but doesn't have metadata for this specific episode number,
        // use a default episode title rather than failing the whole rip
        if epMatch == nil {
            AppLogger.warning("No episode metadata found on OMDb for \(matchedSeries.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode)) — using fallback episode title.")
            epMatch = TVEpisodeMatch(
                seriesTitle: matchedSeries.title,
                seriesYear: matchedSeries.year,
                seriesImdbId: matchedSeries.imdbId,
                season: season,
                episode: episode,
                episodeTitle: "Episode \(episode)",
                episodeImdbId: matchedSeries.imdbId
            )
        }

        guard let ep = epMatch else {
            logUnmatched(fileURL: activeURL)
            AppLogger.error("No IMDb episode match — logged to unmatched.log")
            Notifier.notify(title: "Rip Pipeline ⚠️", message: "\(matchedSeries.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "No episode match for S\(season)E\(episode)"
            ))
            return nil
        }

        return .tvEpisode(
            series: TVSeriesInfo(title: matchedSeries.title, year: matchedSeries.year, imdbId: matchedSeries.imdbId),
            episode: ep,
            season: season,
            episodeNumber: episode
        )
    }

    // MARK: - TV Convenience Entry Points

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
        guard let r1 = Range(match.range(at: 1), in: stem),
              let r2 = Range(match.range(at: 2), in: stem),
              let matchRange = Range(match.range, in: stem) else { return }

        let season = Int(stem[r1]) ?? 1
        let episode = Int(stem[r2]) ?? 1
        let seriesRaw = String(stem[..<matchRange.lowerBound])
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))

        await process(
            fileURL: fileURL,
            workingURL: workingURL,
            tvHint: TVEpisodeHint(seriesTitle: seriesRaw, season: season, episode: episode),
            sourceTypeHint: sourceType,
            outputDir: outputDir,
            forceSubs: forceSubs,
            delegate: delegate
        )
    }

    public func processTVEpisode(
        fileURL: URL,
        workingURL: URL? = nil,
        stem: String,
        seriesTitle: String,
        season: Int,
        episode: Int,
        sourceType: SourceType? = nil,
        outputDir: URL?,
        forceSubs: Bool,
        delegate: PipelineDelegate? = nil
    ) async {
        await process(
            fileURL: fileURL,
            workingURL: workingURL,
            tvHint: TVEpisodeHint(seriesTitle: seriesTitle, season: season, episode: episode),
            sourceTypeHint: sourceType,
            outputDir: outputDir,
            forceSubs: forceSubs,
            delegate: delegate
        )
    }
}
