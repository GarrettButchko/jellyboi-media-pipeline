import Foundation
import LoggingKit

extension Pipeline {
    func remuxTracks(
        target: PipelineMediaTarget,
        fileURL: URL,
        workingURL: URL,
        srtURL: URL?,
        delegate: PipelineDelegate?
    ) async {
        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .remuxingTracks,
            progressFraction: 0.85,
            detail: target.isTV ? "Remuxing tracks…" : "Remuxing clean audio and subtitle tracks…"
        ))

        try? await trackRemuxer.stripTracks(fileURL: workingURL, srtURL: srtURL, config: config)
        if config.clearDefaultSubtitleFlags {
            try? await trackRemuxer.clearSubtitleDefaults(fileURL: workingURL, config: config)
        }
        Notifier.notify(title: "Rip Pipeline", message: target.displayTitle, subtitle: "Tracks remuxed")
    }

    func applyCropIfDetected(
        target: PipelineMediaTarget,
        fileURL: URL,
        workingURL: URL,
        crop: CropEdges?,
        delegate: PipelineDelegate?
    ) async {
        guard let validCrop = crop else { return }
        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .applyingCrop,
            progressFraction: 0.90,
            detail: target.isTV ? "Applying crop metadata…" : "Writing crop metadata into MKV header…"
        ))
        try? await cropDetector.applyCrop(fileURL: workingURL, crop: validCrop)
        Notifier.notify(title: "Rip Pipeline", message: target.displayTitle, subtitle: "Crop metadata applied")
    }
}
