import Foundation
import LoggingKit

extension Pipeline {
    func resolveAndProcessSubtitles(
        target: PipelineMediaTarget,
        fileURL: URL,
        workingURL: URL,
        fileName: String,
        sourceType: SourceType,
        inspection: MediaInspectionResult,
        forceSubs: Bool,
        delegate: PipelineDelegate?
    ) async -> SubtitleResolutionResult {
        var srtData: Data? = nil
        var embeddedSrt = false

        if !forceSubs && inspection.hasEmbeddedSub && config.preferEmbeddedSubs {
            AppLogger.info("Embedded subtitle matching retention policy found — keeping it.")
            embeddedSrt = true
        } else {
            let detail = target.isTV ? "Fetching matching TV episode subtitles…" : "Fetching matching subtitles from OpenSubtitles…"
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .processingSubtitles,
                progressFraction: 0.65,
                detail: detail
            ))

            let preferExtended = preferExtendedCut(for: target, fileName: fileName)
            srtData = await openSubtitlesClient.fetchSubtitles(
                imdbId: target.imdbId,
                sourceType: sourceType,
                mediaType: target.openSubtitlesMediaType,
                preferExtended: preferExtended,
                mkvURL: workingURL,
                videoDuration: inspection.videoDuration,
                videoFPS: inspection.videoFPS,
                processor: subtitleProcessor,
                config: config,
                promptProvider: titlePromptProvider,
                mediaTitle: target.displayTitle
            )
            embeddedSrt = (srtData == nil) && inspection.hasEmbeddedSub
        }

        var srtTmpURL: URL? = nil
        var normalizedEmbedded = false

        if embeddedSrt {
            if config.normalizeEmbeddedAllCaps {
                normalizedEmbedded = (try? await trackRemuxer.normalizeEmbeddedSubtitles(fileURL: workingURL, config: config)) ?? false
            }
            Notifier.notify(
                title: "Rip Pipeline",
                message: target.displayTitle,
                subtitle: normalizedEmbedded ? "Embedded ALL-CAPS subtitles normalized" : "Embedded subtitles kept"
            )
        } else if var subData = srtData {
            let detail = target.isTV ? "Synchronizing TV episode subtitles (alass)…" : "Cleaning ads and syncing subtitle speech…"
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .processingSubtitles,
                progressFraction: 0.75,
                detail: detail
            ))

            if config.stripSubtitleAds {
                subData = SubtitleProcessor.stripSubtitleAds(data: subData)
            }
            if config.stripSubtitleFormatting {
                subData = SubtitleProcessor.stripSubtitleFormatting(data: subData)
            }
            if config.normalizeSubtitleCase {
                subData = SubtitleProcessor.normalizeSubtitleCase(data: subData)
            }
            if config.syncSubtitlesAudio {
                subData = await syncSubtitles(
                    target: target,
                    subData: subData,
                    workingURL: workingURL,
                    videoDuration: inspection.videoDuration,
                    sourceType: sourceType
                )
            }

            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pipeline_sub.srt")
            if (try? subData.write(to: tmp)) != nil {
                srtTmpURL = tmp
            }
            Notifier.notify(title: "Rip Pipeline", message: target.displayTitle, subtitle: "Subtitles downloaded & synced")
        } else {
            logUnmatchedSubs(fileURL: workingURL, imdbId: target.imdbId, sourceType: sourceType)
            Notifier.notify(title: "Rip Pipeline", message: target.displayTitle, subtitle: "No subtitles found")
        }

        return SubtitleResolutionResult(
            srtTmpURL: srtTmpURL,
            normalizedEmbedded: normalizedEmbedded,
            embeddedSrt: embeddedSrt,
            srtData: srtData
        )
    }

    func syncSubtitles(
        target: PipelineMediaTarget,
        subData: Data,
        workingURL: URL,
        videoDuration: Double?,
        sourceType: SourceType
    ) async -> Data {
        switch target {
        case .movie:
            return await subtitleProcessor.syncSubtitlesMovie(srtData: subData, mkvURL: workingURL)
        case .tvEpisode:
            return await subtitleProcessor.syncSubtitlesTV(
                srtData: subData,
                mkvURL: workingURL,
                videoDuration: videoDuration,
                sourceType: sourceType
            )
        }
    }

    func preferExtendedCut(for target: PipelineMediaTarget, fileName: String) -> Bool {
        switch target {
        case .movie(_, let parsedTitle):
            let cutPattern = #"extended|redux|director'?s cut|unrated|special edition"#
            guard let r = try? NSRegularExpression(pattern: cutPattern, options: .caseInsensitive) else {
                return config.preferExtendedCuts
            }
            let inTitle = parsedTitle.map { r.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil } ?? false
            let inName = r.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)) != nil
            return inTitle || inName || config.preferExtendedCuts
        case .tvEpisode:
            return false
        }
    }
}
