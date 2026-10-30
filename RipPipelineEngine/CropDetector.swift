import Foundation

public struct CropDetector: Sendable {
    private let toolRegistry: ToolRegistry
    private let inspector: MediaInspector

    public init(toolRegistry: ToolRegistry = .shared, inspector: MediaInspector = MediaInspector()) {
        self.toolRegistry = toolRegistry
        self.inspector = inspector
    }

    public func detectCrop(fileURL: URL) async throws -> CropEdges? {
        guard let hb = toolRegistry.handBrakeCLI else {
            Logger.warning("HandBrakeCLI not found — skipping crop detection.")
            return nil
        }

        Logger.info("Running HandBrakeCLI scan for crop…")
        let res = try await ProcessRunner.run(
            executable: hb,
            arguments: ["--scan", "-i", fileURL.path],
            timeout: 180
        )

        let combinedOutput = res.stdout + res.stderr
        let pattern = #"autocrop\s*=\s*(\d+)/(\d+)/(\d+)/(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        guard let match = regex.firstMatch(in: combinedOutput, range: NSRange(combinedOutput.startIndex..., in: combinedOutput)),
              let r1 = Range(match.range(at: 1), in: combinedOutput),
              let r2 = Range(match.range(at: 2), in: combinedOutput),
              let r3 = Range(match.range(at: 3), in: combinedOutput),
              let r4 = Range(match.range(at: 4), in: combinedOutput) else {
            Logger.info("HandBrakeCLI found no crop.")
            return nil
        }

        let top = Int(combinedOutput[r1]) ?? 0
        let bottom = Int(combinedOutput[r2]) ?? 0
        let left = Int(combinedOutput[r3]) ?? 0
        let right = Int(combinedOutput[r4]) ?? 0

        let edges = CropEdges(top: top, bottom: bottom, left: left, right: right, minPx: 8)
        if !edges.isMeaningful {
            Logger.info("Crop edges too small — skipping.")
            return nil
        }

        Logger.info("Crop edges — top=\(edges.top) bottom=\(edges.bottom) left=\(edges.left) right=\(edges.right)")
        return edges
    }

    public func applyCrop(fileURL: URL, crop: CropEdges) async throws {
        guard let mkvpropedit = toolRegistry.mkvpropedit else {
            throw ProcessError.executableNotFound("mkvpropedit")
        }

        Logger.info("Applying crop metadata to MKV (no re-encode)…")
        var args = [
            fileURL.path,
            "--edit", "track:v1",
            "--set", "pixel-crop-top=\(crop.top)",
            "--set", "pixel-crop-bottom=\(crop.bottom)",
            "--set", "pixel-crop-left=\(crop.left)",
            "--set", "pixel-crop-right=\(crop.right)"
        ]

        if let dims = try? await inspector.getVideoDimensions(fileURL: fileURL) {
            let newWidth = dims.width - crop.left - crop.right
            let newHeight = dims.height - crop.top - crop.bottom
            let displayWidth = Int(round(Double(newWidth) * dims.par))

            args.append(contentsOf: [
                "--set", "display-unit=0",
                "--set", "display-width=\(displayWidth)",
                "--set", "display-height=\(newHeight)"
            ])
            Logger.info("Recomputed aspect ratio for crop — display \(displayWidth)x\(newHeight) (was \(dims.width)x\(dims.height))")
        } else {
            Logger.warning("Could not read video dimensions — aspect ratio metadata left unchanged.")
        }

        let res = try await ProcessRunner.run(executable: mkvpropedit, arguments: args)
        if !res.isSuccess {
            Logger.warning("mkvpropedit crop application failed: \(res.stderr)")
        } else {
            Logger.info("Crop metadata applied.")
        }
    }
}
