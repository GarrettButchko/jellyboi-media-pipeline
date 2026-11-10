import Foundation
import LoggingKit

extension Pipeline {
    // MARK: - Movie Metadata Resolution Area

    func resolveMovieMetadata(
        fileURL: URL,
        workingURL: URL,
        stem: String,
        aiSuggestion: MediaQuerySuggestion?,
        delegate: PipelineDelegate?
    ) async -> PipelineMediaTarget? {
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

        // If the heuristic title failed, retry once with the on-device model's
        // cleaned-up name. This is a fallback only, so well-named movies never
        // wait on the model.
        if matchedMovie == nil,
           let ai = aiSuggestion,
           !ai.isTVEpisode,
           !ai.searchTitle.isEmpty,
           ai.searchTitle.caseInsensitiveCompare(parsed.title) != .orderedSame {
            AppLogger.warning("Heuristic title '\(parsed.title)' had no IMDb match — retrying with on-device query '\(ai.searchTitle)'")
            matchedMovie = await omdbClient.resolveMovie(
                title: ai.searchTitle,
                yearHint: ai.year.map(String.init) ?? parsed.yearHint,
                durationMinutes: parsed.durationMinutes,
                inspector: inspector,
                fileURL: workingURL
            )
        }

        // Title Disambiguation: if no automatic match, search OMDb for closest titles and present ranked choices
        if matchedMovie == nil, config.promptForAmbiguousTitles, let promptProvider = titlePromptProvider {
            let searchTitle = aiSuggestion?.searchTitle ?? parsed.title
            let searchYear = parsed.yearHint.flatMap(Int.init) ?? aiSuggestion?.year
            let candidates = await omdbClient.search(title: searchTitle, year: searchYear)
            if !candidates.isEmpty {
                await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                    fileURL: fileURL,
                    stage: .awaitingTitle,
                    progressFraction: 0.38,
                    detail: "Multiple title matches found for '\(searchTitle)'. Please confirm the correct title."
                ))

                if let chosen = await promptProvider.promptForTitleDisambiguation(
                    fileURL: workingURL,
                    originalQuery: searchTitle,
                    candidates: candidates
                ) {
                    matchedMovie = MovieMatch(
                        title: chosen.title,
                        year: chosen.year,
                        imdbId: chosen.imdbId,
                        votes: chosen.votes,
                        runtimeMinutes: chosen.runtimeMinutes
                    )
                }
            }
        }

        // If still no match found, prompt user to enter a new title or IMDb ID,
        // search that title (running through the on-device AI model if available),
        // offer disambiguation if needed, and repeat until matched or cancelled.
        var currentPromptTitle = parsed.title
        var searchFailureDetail: String? = nil

        while matchedMovie == nil, let promptProvider = titlePromptProvider {
            AppLogger.warning("No automatic IMDb match for '\(currentPromptTitle)'. Requesting user input…")
            let promptDetail = searchFailureDetail ?? "No IMDb match found for '\(currentPromptTitle)'. Please enter the correct title or IMDb ID."
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .awaitingTitle,
                progressFraction: 0.38,
                detail: promptDetail
            ))

            // Fetch candidate suggestions from AI if available
            var candidates: [String] = []
            if MediaQueryAssistant.isAvailable {
                let parentDir = workingURL.deletingLastPathComponent().lastPathComponent
                candidates = await MediaQueryAssistant.suggestDiscRipCandidates(
                    fileName: currentPromptTitle,
                    parentFolder: (parentDir.isEmpty || parentDir == "/") ? nil : parentDir
                )
            }

            guard let retryTitle = await promptProvider.promptForTitle(
                fileURL: workingURL,
                suggestedTitle: candidates.first ?? (currentPromptTitle.isEmpty ? nil : currentPromptTitle),
                candidates: candidates,
                reason: .emptyOrGenericMetadata
            ), !retryTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
                // User cancelled or skipped
                AppLogger.info("User cancelled or skipped title entry for: \(workingURL.lastPathComponent)")
                break
            }

            let trimmed = retryTitle.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased() == "skip" {
                AppLogger.info("User explicitly skipped title entry.")
                break
            }

            currentPromptTitle = trimmed

            // 1. Check if user entered an IMDb ID directly (e.g. tt1234567)
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
                    break
                } else {
                    searchFailureDetail = "Could not find any IMDb entry for ID '\(trimmed)'. Please try another title or ID."
                    continue
                }
            }

            // 2. Check if the user input contains a TV episode pattern (e.g. "Psych S02E11" or "Breaking Bad 1x03")
            if let tvInfo = Self.parseTVEpisodeInfo(from: trimmed) {
                AppLogger.info("TV episode detected from user title: '\(tvInfo.seriesTitle)' S\(String(format: "%02d", tvInfo.season))E\(String(format: "%02d", tvInfo.episode))")
                return await resolveTVMetadata(
                    fileURL: fileURL,
                    workingURL: workingURL,
                    stem: trimmed,
                    seriesTitle: tvInfo.seriesTitle.isEmpty ? trimmed : tvInfo.seriesTitle,
                    season: tvInfo.season,
                    episode: tvInfo.episode,
                    delegate: delegate
                )
            }

            // 3. If there is a model, run through the model again
            var searchTitle = trimmed
            var searchYear: String? = nil

            if MediaQueryAssistant.isAvailable {
                await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                    fileURL: fileURL,
                    stage: .extractingMetadata,
                    progressFraction: 0.38,
                    detail: "Analyzing '\(trimmed)' with on-device AI…"
                ))

                if let ai = await MediaQueryAssistant.suggestSearchName(forFileNamed: trimmed) {
                    if ai.isTVEpisode, let season = ai.season, let episode = ai.episode, !ai.searchTitle.isEmpty {
                        AppLogger.info("On-device AI detected TV episode from user title: '\(ai.searchTitle)' S\(String(format: "%02d", season))E\(String(format: "%02d", episode))")
                        return await resolveTVMetadata(
                            fileURL: fileURL,
                            workingURL: workingURL,
                            stem: trimmed,
                            seriesTitle: ai.searchTitle,
                            season: season,
                            episode: episode,
                            delegate: delegate
                        )
                    }

                    if !ai.searchTitle.isEmpty {
                        searchTitle = ai.searchTitle
                        searchYear = ai.year.map(String.init)
                    }
                }
            } else {
                let sanitized = TitleSanitizer.sanitize(rawTitle: trimmed)
                searchTitle = sanitized.title
                searchYear = sanitized.year.map(String.init)
            }

            // 4. Search OMDb for the movie
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .matchingMetadata,
                progressFraction: 0.39,
                detail: "Searching IMDb for '\(searchTitle)'…"
            ))

            matchedMovie = await omdbClient.resolveMovie(
                title: searchTitle,
                yearHint: searchYear ?? parsed.yearHint,
                durationMinutes: parsed.durationMinutes,
                inspector: inspector,
                fileURL: workingURL
            )

            // If still no direct match, check if ambiguous candidates exist
            if matchedMovie == nil, config.promptForAmbiguousTitles {
                let candidates = await omdbClient.search(title: searchTitle, year: searchYear.flatMap(Int.init))
                if !candidates.isEmpty {
                    await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                        fileURL: fileURL,
                        stage: .awaitingTitle,
                        progressFraction: 0.39,
                        detail: "Multiple title matches found for '\(searchTitle)'. Please confirm the correct title."
                    ))

                    if let chosen = await promptProvider.promptForTitleDisambiguation(
                        fileURL: workingURL,
                        originalQuery: searchTitle,
                        candidates: candidates
                    ) {
                        matchedMovie = MovieMatch(
                            title: chosen.title,
                            year: chosen.year,
                            imdbId: chosen.imdbId,
                            votes: chosen.votes,
                            runtimeMinutes: chosen.runtimeMinutes
                        )
                    }
                }
            }

            if matchedMovie != nil {
                AppLogger.info("Successfully matched user-provided title: '\(matchedMovie!.title) (\(matchedMovie!.year))'")
                break
            } else {
                searchFailureDetail = "No IMDb match found for '\(searchTitle)'. Please try another title or IMDb ID."
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
            return nil
        }

        return .movie(match: movie, parsedTitle: parsed.title)
    }
}
