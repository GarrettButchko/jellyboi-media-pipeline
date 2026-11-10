import Foundation
import LoggingKit

extension Pipeline {
    func moveMediaToLibrary(
        target: PipelineMediaTarget,
        fileURL: URL,
        workingURL: URL,
        outputDir: URL?,
        delegate: PipelineDelegate?
    ) async -> URL? {
        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .movingToLibrary,
            progressFraction: 0.95,
            detail: target.isTV ? "Moving to TV library…" : "Moving to organized library…"
        ))

        let destURL: URL?
        switch target {
        case .movie(let movie, _):
            let libraryDir = outputDir ?? config.libraryDir
            destURL = try? LibraryOrganizer.moveToLibrary(
                srcURL: workingURL,
                title: movie.title,
                year: movie.year,
                imdbId: movie.imdbId,
                libraryDir: libraryDir
            )
        case .tvEpisode(let series, let ep, let season, let episodeNumber):
            let tvLibraryDir = outputDir ?? config.tvLibraryDir
            destURL = try? LibraryOrganizer.moveToTVLibrary(
                srcURL: workingURL,
                seriesTitle: series.title,
                seriesYear: series.year,
                seriesImdbId: series.imdbId,
                season: season,
                episode: episodeNumber,
                episodeTitle: ep.episodeTitle,
                tvLibraryDir: tvLibraryDir
            )
        }

        guard let dest = destURL else {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: target.isTV ? "Failed to move TV episode to library" : "Failed to move file to destination library"
            ))
            return nil
        }

        return dest
    }

    func finalizePipeline(
        target: PipelineMediaTarget,
        fileURL: URL,
        destinationURL: URL,
        subResult: SubtitleResolutionResult,
        delegate: PipelineDelegate?
    ) async {
        let subStatus = subResult.normalizedEmbedded ? "embedded subtitles normalized" :
            (subResult.embeddedSrt ? "embedded subtitles kept" :
            (subResult.srtData != nil ? "with subtitles (embedded)" : "no subtitles"))

        let destSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useGB, .useMB]
        bcf.countStyle = .file
        let sizeStr = bcf.string(fromByteCount: destSize)

        AppLogger.success("Finished: \(destinationURL.lastPathComponent) (\(sizeStr))")
        Notifier.notify(title: "Rip Pipeline ✓", message: target.displayTitle, subtitle: "\(sizeStr) — \(subStatus)")

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            destinationURL: destinationURL,
            stage: .completed,
            progressFraction: 1.0,
            detail: "Successfully processed (\(subStatus))"
        ))
    }
}
