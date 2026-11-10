import Foundation
import LoggingKit

extension Pipeline {
    func detectSourceType(
        fileURL: URL,
        workingURL: URL,
        fileName: String,
        delegate: PipelineDelegate?
    ) async -> SourceType {
        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .detectingSource,
            progressFraction: 0.15,
            detail: "Inspecting media streams…"
        ))

        let sourceType = (try? await inspector.detectSourceType(fileURL: workingURL)) ?? .bluray
        Notifier.notify(title: "Rip Pipeline", message: fileName, subtitle: "Detected: \(sourceType.displayTitle)")
        return sourceType
    }

    func inspectMediaStreams(
        fileURL: URL,
        workingURL: URL,
        delegate: PipelineDelegate?
    ) async -> MediaInspectionResult {
        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .detectingCrop,
            progressFraction: 0.50,
            detail: "Detecting video crop and inspecting subtitle tracks…"
        ))

        let mediaURL = workingURL
        async let cropTask = try? cropDetector.detectCrop(fileURL: mediaURL)
        async let durationTask = try? inspector.getDecodedDuration(fileURL: mediaURL)
        async let hasEligibleEmbeddedTask = try? inspector.hasEligibleEmbeddedSubtitle(fileURL: mediaURL, config: config)
        async let videoFPSTask = try? inspector.getVideoFPS(fileURL: mediaURL)

        let hasEmbeddedSub = (await hasEligibleEmbeddedTask) ?? false
        let videoDuration = await durationTask
        let videoFPS = await videoFPSTask
        let crop = await cropTask

        return MediaInspectionResult(
            crop: crop,
            videoDuration: videoDuration,
            hasEmbeddedSub: hasEmbeddedSub,
            videoFPS: videoFPS
        )
    }
}
