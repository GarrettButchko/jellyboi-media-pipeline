import Foundation
import LoggingKit

extension Pipeline {
    func resolveMediaTarget(
        fileURL: URL,
        workingURL: URL,
        tvHint: TVEpisodeHint?,
        delegate: PipelineDelegate?
    ) async -> PipelineMediaTarget? {
        let stem = workingURL.deletingPathExtension().lastPathComponent

        // Explicit TV Hint from caller
        if let tvHint = tvHint {
            return await resolveTVMetadata(
                fileURL: fileURL,
                workingURL: workingURL,
                stem: stem,
                seriesTitle: tvHint.seriesTitle,
                season: tvHint.season,
                episode: tvHint.episode,
                delegate: delegate
            )
        }

        // TV Episode detection: filename contains SxxExx, 1x02, or Season 1 Episode 2
        if let tvInfo = Self.parseTVEpisodeInfo(from: stem) {
            return await resolveTVMetadata(
                fileURL: fileURL,
                workingURL: workingURL,
                stem: stem,
                seriesTitle: tvInfo.seriesTitle.isEmpty ? stem : tvInfo.seriesTitle,
                season: tvInfo.season,
                episode: tvInfo.episode,
                delegate: delegate
            )
        }

        // On-device AI model check for TV episode / movie query
        var aiSuggestion: MediaQuerySuggestion? = nil
        if MediaQueryAssistant.isAvailable {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .extractingMetadata,
                progressFraction: 0.20,
                detail: "Reading file name with the on-device model…"
            ))
            aiSuggestion = await MediaQueryAssistant.suggestSearchName(forFileNamed: stem)
        }

        if let ai = aiSuggestion,
           ai.isTVEpisode,
           let season = ai.season,
           let episode = ai.episode,
           !ai.searchTitle.isEmpty {
            AppLogger.info("On-device AI detected TV episode: '\(ai.searchTitle)' S\(String(format: "%02d", season))E\(String(format: "%02d", episode))")
            return await resolveTVMetadata(
                fileURL: fileURL,
                workingURL: workingURL,
                stem: stem,
                seriesTitle: ai.searchTitle,
                season: season,
                episode: episode,
                delegate: delegate
            )
        }

        // Movie metadata resolution
        return await resolveMovieMetadata(
            fileURL: fileURL,
            workingURL: workingURL,
            stem: stem,
            aiSuggestion: aiSuggestion,
            delegate: delegate
        )
    }
}
