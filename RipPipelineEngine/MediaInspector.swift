import Foundation

/// Fast metadata inspection, source detection, and duration probing for media files.
public struct MediaInspector: Sendable {
    private let toolRegistry: ToolRegistry

    public init(toolRegistry: ToolRegistry = .shared) {
        self.toolRegistry = toolRegistry
    }

    // MARK: - Source Type Detection (DVD vs Blu-ray)

    public func detectSourceType(fileURL: URL) async throws -> SourceType {
        guard let ffprobe = toolRegistry.ffprobe else {
            throw ProcessError.executableNotFound("ffprobe")
        }

        let res = try await ProcessRunner.run(
            executable: ffprobe,
            arguments: [
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=codec_name,height",
                "-of", "json",
                fileURL.path
            ]
        )

        var codec = ""
        var height = 0

        if let json = try? JSONSerialization.jsonObject(with: res.stdoutData) as? [String: Any],
           let streams = json["streams"] as? [[String: Any]],
           let first = streams.first {
            codec = (first["codec_name"] as? String)?.lowercased() ?? ""
            height = (first["height"] as? Int) ?? 0
        }

        let isMpeg2 = codec.contains("mpeg2")
        let isSdHeight = height > 0 && height <= 576
        let result: SourceType = (isMpeg2 || isSdHeight) ? .dvd : .bluray

        Logger.info("Source type: \(result == .dvd ? "DVD" : "BLURAY")  (codec=\(codec) height=\(height))")
        return result
    }

    // MARK: - Title and Metadata Extraction

    public func extractTitleAndMetadata(fileURL: URL) async throws -> ParsedTitle {
        guard let ffprobe = toolRegistry.ffprobe else {
            throw ProcessError.executableNotFound("ffprobe")
        }

        let res = try await ProcessRunner.run(
            executable: ffprobe,
            arguments: [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                fileURL.path
            ]
        )

        var rawTitle = ""
        var durationMinutes: Double? = nil
        var isFromMetadata = false

        if let json = try? JSONSerialization.jsonObject(with: res.stdoutData) as? [String: Any],
           let format = json["format"] as? [String: Any] {
            if let durationStr = format["duration"] as? String, let sec = Double(durationStr) {
                durationMinutes = sec / 60.0
            }
            if let tags = format["tags"] as? [String: Any],
               let titleTag = tags["title"] as? String, !titleTag.trimmingCharacters(in: .whitespaces).isEmpty {
                rawTitle = titleTag.trimmingCharacters(in: .whitespaces)
                isFromMetadata = true
            }
        }

        if rawTitle.isEmpty {
            rawTitle = fileURL.deletingPathExtension().lastPathComponent
            isFromMetadata = false
        }

        let sanitized = TitleSanitizer.sanitize(rawTitle: rawTitle)
        let yearString = sanitized.year != nil ? String(sanitized.year!) : nil
        Logger.info("Disc title: \(sanitized.title)\(yearString != nil ? " (\(yearString!))" : "")")
        return ParsedTitle(
            title: sanitized.title,
            yearHint: yearString,
            durationMinutes: durationMinutes,
            isFromMetadata: isFromMetadata
        )
    }

    // MARK: - Video Dimensions & Aspect Ratio

    public func getVideoDimensions(fileURL: URL) async throws -> VideoDimensions? {
        guard let ffprobe = toolRegistry.ffprobe else {
            throw ProcessError.executableNotFound("ffprobe")
        }

        let res = try await ProcessRunner.run(
            executable: ffprobe,
            arguments: [
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height,sample_aspect_ratio",
                "-of", "json",
                fileURL.path
            ]
        )

        guard let json = try? JSONSerialization.jsonObject(with: res.stdoutData) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]],
              let first = streams.first,
              let width = first["width"] as? Int,
              let height = first["height"] as? Int else {
            return nil
        }

        var parWidth = 1
        var parHeight = 1
        if let sar = first["sample_aspect_ratio"] as? String, sar.contains(":") {
            let parts = sar.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 && parts[0] > 0 && parts[1] > 0 {
                parWidth = parts[0]
                parHeight = parts[1]
            }
        }

        let parValue = Double(parWidth) / Double(parHeight)
        return VideoDimensions(
            width: width,
            height: height,
            par: parValue
        )
    }

    // MARK: - Video FPS

    public func getVideoFPS(fileURL: URL) async throws -> Double? {
        guard let ffprobe = toolRegistry.ffprobe else {
            throw ProcessError.executableNotFound("ffprobe")
        }

        let res = try await ProcessRunner.run(
            executable: ffprobe,
            arguments: [
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=r_frame_rate",
                "-of", "json",
                fileURL.path
            ]
        )

        guard let json = try? JSONSerialization.jsonObject(with: res.stdoutData) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]],
              let first = streams.first,
              let rateStr = first["r_frame_rate"] as? String else {
            return nil
        }

        let parts = rateStr.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2 && parts[1] > 0 else { return nil }
        let fps = parts[0] / parts[1]
        guard fps > 0 else { return nil }
        return fps
    }

    // MARK: - Fast Tail Duration Extraction Optimization

    public func getDecodedDuration(fileURL: URL) async throws -> Double? {
        guard let ffprobe = toolRegistry.ffprobe else {
            throw ProcessError.executableNotFound("ffprobe")
        }

        let probeRes = try await ProcessRunner.run(
            executable: ffprobe,
            arguments: [
                "-v", "error",
                "-show_entries", "format=duration:stream=duration",
                "-of", "json",
                fileURL.path
            ]
        )

        var durations: [Double] = []
        if let json = try? JSONSerialization.jsonObject(with: probeRes.stdoutData) as? [String: Any] {
            if let format = json["format"] as? [String: Any],
               let durStr = format["duration"] as? String,
               let dur = Double(durStr), dur > 0 {
                durations.append(dur)
            }
            if let streams = json["streams"] as? [[String: Any]] {
                for s in streams {
                    if let durStr = s["duration"] as? String,
                       let dur = Double(durStr), dur > 0 {
                        durations.append(dur)
                    }
                }
            }
        }

        if !durations.isEmpty {
            let minDur = durations.min()!
            let maxDur = durations.max()!
            if maxDur - minDur <= 3.0 {
                return minDur
            }
        }

        guard let ffmpeg = toolRegistry.ffmpeg else {
            return durations.first
        }

        let tailRes = try? await ProcessRunner.run(
            executable: ffmpeg,
            arguments: [
                "-sseof", "-60",
                "-i", fileURL.path,
                "-map", "0:v:0",
                "-c", "copy",
                "-f", "null",
                "-"
            ],
            timeout: 60
        )

        if let output = tailRes?.stderr {
            let pattern = #"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
                if let last = matches.last,
                   let r1 = Range(last.range(at: 1), in: output),
                   let r2 = Range(last.range(at: 2), in: output),
                   let r3 = Range(last.range(at: 3), in: output) {
                    let h = Double(output[r1]) ?? 0
                    let m = Double(output[r2]) ?? 0
                    let s = Double(output[r3]) ?? 0
                    let tailDuration = h * 3600 + m * 60 + s
                    if tailDuration > 0 {
                        return tailDuration
                    }
                }
            }
        }

        return durations.first
    }

    // MARK: - Track Discovery

    public func getMKVTracks(fileURL: URL) async throws -> [MKVTrack] {
        guard let mkvmerge = toolRegistry.mkvmerge else {
            throw ProcessError.executableNotFound("mkvmerge")
        }

        let res = try await ProcessRunner.run(
            executable: mkvmerge,
            arguments: ["-J", fileURL.path]
        )

        guard let json = try? JSONSerialization.jsonObject(with: res.stdoutData) as? [String: Any],
              let tracks = json["tracks"] as? [[String: Any]] else {
            return []
        }

        var result: [MKVTrack] = []
        for t in tracks {
            guard let id = t["id"] as? Int,
                  let type = t["type"] as? String else { continue }

            let codec = (t["codec"] as? String) ?? ""
            let properties = (t["properties"] as? [String: Any]) ?? [:]
            let codecId = (properties["codec_id"] as? String) ?? (t["codec_id"] as? String) ?? ""
            let language = (properties["language"] as? String) ?? ""
            let isDefault = (properties["default_track"] as? Bool) ?? false
            let isForced = (properties["forced_track"] as? Bool) ?? false

            result.append(MKVTrack(
                id: id,
                type: type,
                codec: codec,
                codecId: codecId,
                language: language,
                isDefault: isDefault,
                isForced: isForced
            ))
        }

        return result
    }

    public func hasEnglishSubRipSubtitle(fileURL: URL) async throws -> Bool {
        let tracks = try await getMKVTracks(fileURL: fileURL)
        return tracks.contains { $0.isEnglishSubtitle && $0.isSubRip }
    }
}
