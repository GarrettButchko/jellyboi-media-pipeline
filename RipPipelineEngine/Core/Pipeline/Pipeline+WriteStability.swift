import Foundation
import LoggingKit

extension Pipeline {
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
}
