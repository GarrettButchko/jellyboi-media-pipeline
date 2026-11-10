import SwiftUI
import BaseColors
import LoggingKit

#if DEBUG
@MainActor
public enum ScreenshotDemoHelper {
    public static func populateRemuxQueue(manager: PipelineManager) {
        withAnimation(.smooth(duration: 0.25)) {
            manager.queue.removeAll()

            // 1. Running remux item
            var runningItem = QueueItem(fileURL: URL(fileURLWithPath: "/Volumes/Media/Rips/Blade_Runner_2049_t00.mkv"))
            runningItem.initialSizeBytes = 34_359_738_368 // 32.0 GB
            runningItem.stage = .remuxingTracks
            runningItem.status = .running
            runningItem.progressFraction = 0.85
            runningItem.statusDetail = "Remuxing clean audio and subtitle tracks…"

            // 2. Active crop detection item
            var cropItem = QueueItem(fileURL: URL(fileURLWithPath: "/Volumes/Media/Rips/Dune_Part_Two_t01.mkv"))
            cropItem.initialSizeBytes = 41_875_931_136 // 39.0 GB
            cropItem.stage = .detectingCrop
            cropItem.status = .running
            cropItem.progressFraction = 0.50
            cropItem.statusDetail = "Detecting video crop and inspecting subtitle tracks…"

            // 3. Completed item with remux track filtering (foreign audio & commentary stripped)
            var completedItem = QueueItem(fileURL: URL(fileURLWithPath: "/Volumes/Media/Rips/Inception_t00.mkv"))
            completedItem.initialSizeBytes = 28_991_029_248 // 27.0 GB
            completedItem.finalSizeBytes = 24_696_061_952 // 23.0 GB (-15%)
            completedItem.stage = .completed
            completedItem.status = .completed
            completedItem.progressFraction = 1.0
            completedItem.statusDetail = "Successfully processed (23.0 GB, with subtitles (embedded))"
            completedItem.completedURL = URL(fileURLWithPath: "/Volumes/Media/Movies/Inception (2010)/Inception (2010).mkv")

            // 4. Queued item awaiting processing
            var queuedItem = QueueItem(fileURL: URL(fileURLWithPath: "/Volumes/Media/Rips/Interstellar_2014_t00.mkv"))
            queuedItem.initialSizeBytes = 31_138_512_896 // 29.0 GB
            queuedItem.stage = .queued
            queuedItem.status = .queued
            queuedItem.progressFraction = 0.0
            queuedItem.statusDetail = "Queued for processing"

            manager.queue = [runningItem, cropItem, completedItem, queuedItem]
        }
    }

    public static func triggerDiscRipTitlePrompt(manager: PipelineManager) {
        let fakeURL = URL(fileURLWithPath: "/Volumes/Media/Rips/OPPENHEIMER_DISC1_t00.mkv")
        manager.activeTitlePrompt = TitlePromptRequest(
            fileURL: fakeURL,
            suggestedTitle: "Oppenheimer",
            reason: .rawDiscTrack,
            completion: { title in
                if let title = title {
                    AppLogger.info("User provided accurate title: '\(title)'")
                }
                manager.activeTitlePrompt = nil
            }
        )
    }

    public static func triggerTitleDisambiguation(manager: PipelineManager) {
        let fakeURL = URL(fileURLWithPath: "/Volumes/Media/Rips/THE_BATMAN_DISC1_t00.mkv")
        let candidates = [
            OMDbClient.Candidate(
                title: "The Batman",
                year: "2022",
                imdbId: "tt1877830",
                type: "movie",
                votes: 785_420,
                runtimeMinutes: 176
            ),
            OMDbClient.Candidate(
                title: "Batman Begins",
                year: "2005",
                imdbId: "tt0372784",
                type: "movie",
                votes: 1_582_000,
                runtimeMinutes: 140
            ),
            OMDbClient.Candidate(
                title: "The Batman",
                year: "2004–2008",
                imdbId: "tt0398417",
                type: "series",
                votes: 43_250,
                runtimeMinutes: 22
            ),
            OMDbClient.Candidate(
                title: "The Batman vs Dracula",
                year: "2005",
                imdbId: "tt0472219",
                type: "movie",
                votes: 15_600,
                runtimeMinutes: 84
            )
        ]

        manager.activeTitleDisambiguation = TitleDisambiguationRequest(
            fileURL: fakeURL,
            originalQuery: "The Batman",
            candidates: candidates,
            completion: { chosen in
                if let chosen = chosen {
                    AppLogger.info("User disambiguated title to: '\(chosen.title) (\(chosen.year))' [\(chosen.imdbId)]")
                }
                manager.activeTitleDisambiguation = nil
            }
        )
    }

    public static func triggerSubtitleSelection(manager: PipelineManager) {
        let fakeURL = URL(fileURLWithPath: "/Volumes/Media/Rips/Blade_Runner_2049_t00.mkv")
        let candidates = [
            SubtitleCandidate(
                fileId: "19548231",
                release: "Blade.Runner.2049.2017.1080p.BluRay.x264-SPARKS.SDH",
                score: 1,
                downloadCount: 38450,
                hearingImpaired: true,
                fps: 23.976,
                isHDTV: false,
                isCommentary: false,
                isCutVariant: false,
                rejectionReasons: [
                    "Hearing Impaired / SDH (closed captions)"
                ]
            ),
            SubtitleCandidate(
                fileId: "19548234",
                release: "Blade.Runner.2049.2017.720p.HDTV.x264-AVS",
                score: 0,
                downloadCount: 14200,
                hearingImpaired: false,
                fps: 25.000,
                isHDTV: true,
                isCommentary: false,
                isCutVariant: false,
                rejectionReasons: [
                    "FPS mismatch (25.000 vs video 23.976)",
                    "HDTV broadcast release (timing often contains commercial cuts)"
                ]
            ),
            SubtitleCandidate(
                fileId: "19548236",
                release: "Blade.Runner.2049.2017.Extended.Cut.1080p.BluRay.x264-SPARKS",
                score: -1,
                downloadCount: 8920,
                hearingImpaired: false,
                fps: 23.976,
                isHDTV: false,
                isCommentary: false,
                isCutVariant: true,
                rejectionReasons: [
                    "Cut variant (extended / unrated / director's cut)"
                ]
            ),
            SubtitleCandidate(
                fileId: "19548238",
                release: "Blade.Runner.2049.2017.1080p.AMZN.WEBRip.DDP5.1.Atmos.x264-NTG",
                score: 0,
                downloadCount: 6140,
                hearingImpaired: false,
                fps: 29.970,
                isHDTV: false,
                isCommentary: false,
                isCutVariant: false,
                rejectionReasons: [
                    "FPS mismatch (29.970 vs video 23.976)"
                ]
            ),
            SubtitleCandidate(
                fileId: "19548240",
                release: "Blade.Runner.2049.2017.BluRay.Audio.Commentary-Director",
                score: -2,
                downloadCount: 1280,
                hearingImpaired: false,
                fps: 23.976,
                isHDTV: false,
                isCommentary: true,
                isCutVariant: false,
                rejectionReasons: [
                    "Audio commentary subtitle"
                ]
            )
        ]

        manager.activeSubtitlePrompt = SubtitleSelectionRequest(
            fileURL: fakeURL,
            mediaTitle: "Blade Runner 2049 (2017)",
            candidates: candidates,
            completion: { chosen in
                if let chosen = chosen {
                    AppLogger.info("User selected fallback subtitle candidate: '\(chosen.release)'", tag: "OpenSubtitles")
                }
                manager.activeSubtitlePrompt = nil
            }
        )
    }

    public static func populateJellyfinQueue(manager: PipelineManager) {
        withAnimation(.smooth(duration: 0.25)) {
            manager.jellyfinDetectionState = .detected(version: "1.0.6", serverName: "Home Media Server")
            manager.jellyfinDetectedServerURL = "http://192.168.1.100:8096"
            manager.config.jellyfinServerURL = "http://192.168.1.100:8096"
            manager.config.jellyfinUploadEnabled = true

            manager.jellyfinQueue.removeAll()

            // 1. Actively streaming upload
            let uploadingItem = JellyfinUploadItem(
                fileURL: URL(fileURLWithPath: "/Volumes/Media/Movies/Oppenheimer (2023)/Oppenheimer (2023).mkv"),
                fileName: "Oppenheimer (2023).mkv",
                fileSizeBytes: 24_696_061_952, // 23.0 GB
                mediaType: .movie,
                title: "Oppenheimer",
                year: "2023",
                imdbId: "tt15398776",
                targetLibraryId: "movies-lib-uuid",
                status: .uploading,
                progressFraction: 0.73,
                statusDetail: "Uploading (18.0 GB / 24.7 GB)"
            )

            // 2. Completed upload
            let completedItem = JellyfinUploadItem(
                fileURL: URL(fileURLWithPath: "/Volumes/Media/Movies/Dune (2021)/Dune (2021).mkv"),
                fileName: "Dune (2021).mkv",
                fileSizeBytes: 18_253_611_008, // 17.0 GB
                mediaType: .movie,
                title: "Dune",
                year: "2021",
                imdbId: "tt1160419",
                targetLibraryId: "movies-lib-uuid",
                status: .completed,
                progressFraction: 1.0,
                statusDetail: "Uploaded successfully to Jellyfin"
            )

            // 3. Queued upload
            let queuedItem = JellyfinUploadItem(
                fileURL: URL(fileURLWithPath: "/Volumes/Media/TV/Severance/Season 01/Severance S01E01.mkv"),
                fileName: "Severance S01E01.mkv",
                fileSizeBytes: 4_831_838_208, // 4.5 GB
                mediaType: .tvEpisode,
                title: "Severance",
                year: "2022",
                imdbId: "tt11280740",
                season: 1,
                episode: 1,
                episodeTitle: "Good News About Hell",
                targetLibraryId: "tv-lib-uuid",
                status: .queued,
                progressFraction: 0.0,
                statusDetail: "Queued for upload"
            )

            manager.jellyfinQueue = [uploadingItem, completedItem, queuedItem]
        }
    }

    public static func populateLogs(manager: PipelineManager) {
        manager.logs.removeAll()
        let logs: [(LogLevel, String)] = [
            (.info, "=== Processing: Blade_Runner_2049_t00.mkv ==="),
            (.info, "Source type: BLURAY (codec=h264 height=1080)"),
            (.info, "OMDb (exact + year): Blade Runner 2049 (2017) [tt1856101]"),
            (.info, "Running HandBrakeCLI scan for crop…"),
            (.info, "Crop edges — top=140 bottom=140 left=0 right=0"),
            (.info, "Fetching subtitles for tt1856101 (source=bluray)..."),
            (.info, "OpenSubtitles: filtered out 2 fps-mismatch, 1 HDTV, 1 HI, 1 commentary release(s)."),
            (.info, "OpenSubtitles: 3 eligible result(s), best score=1 release='Blade.Runner.2049.2017.1080p.BluRay.x264.DTS-HD.MA.7.1-FGT'"),
            (.info, "Stripped 2 ad/credit cue(s) from subtitles."),
            (.info, "Syncing subtitle timing to audio (ffsubsync)…"),
            (.info, "Subtitle sync complete."),
            (.info, "Keeping 2 audio track(s) (removed 4), keeping 1 subtitle(s) (removed 6)."),
            (.info, "Applying crop metadata to MKV (no re-encode)…"),
            (.info, "Cleared default flag from 1 embedded subtitle track(s)."),
            (.success, "Finished: Blade Runner 2049 (2017).mkv (28.4 GB)"),
            (.info, "[Jellyfin] Directly uploading 'Blade Runner 2049 (2017).mkv' to Jellyfin server (http://192.168.1.100:8096)"),
            (.success, "[Jellyfin] Direct upload finished: Blade Runner 2049 (2017).mkv")
        ]

        let baseDate = Date().addingTimeInterval(-180)
        for (i, (level, msg)) in logs.enumerated() {
            let timestamp = baseDate.addingTimeInterval(Double(i * 10))
            manager.logs.append(AppLogMessage(timestamp: timestamp, level: level, message: msg))
        }
    }

    public static func resetAllMockData(manager: PipelineManager) {
        withAnimation(.smooth(duration: 0.2)) {
            manager.queue.removeAll()
            manager.jellyfinQueue.removeAll()
            manager.logs.removeAll()
            manager.activeTitlePrompt = nil
            manager.activeTitleDisambiguation = nil
            manager.activeSubtitlePrompt = nil
        }
    }
}
#endif
