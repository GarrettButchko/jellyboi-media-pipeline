import Foundation
import LoggingKit

public struct SubtitleProcessor: Sendable {
    private let toolRegistry: ToolRegistry

    public init(toolRegistry: ToolRegistry = .shared) {
        self.toolRegistry = toolRegistry
    }

    // MARK: - Multi-Encoding String Decoding & Encoding

    public nonisolated static func decodeSRT(data: Data) -> String {
        var result: String? = nil

        if data.starts(with: [0xFF, 0xFE]) {
            result = String(data: data, encoding: .utf16LittleEndian)
        } else if data.starts(with: [0xFE, 0xFF]) {
            result = String(data: data, encoding: .utf16BigEndian)
        } else if let str = String(data: data, encoding: .utf8) {
            result = str
        } else if let str = String(data: data, encoding: .windowsCP1252) {
            result = str
        } else if let str = String(data: data, encoding: .isoLatin1) {
            result = str
        } else {
            result = String(decoding: data, as: UTF8.self)
        }

        var text = result ?? ""
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text
    }

    public static func encodeSRT(_ string: String) -> Data {
        string.data(using: .utf8) ?? Data()
    }

    // MARK: - Ad / Credit Stripping

    private static let adCuePattern = #"(?i)opensubtitles|subtitles by|sync(?:ed)? by|resync(?:ed)? by|corrected by|subscene|addic7ed|yts\.(?:mx|am|ag|lt)|advertise your product|support us|become vip|www\.\S+\.\S+|https?://\S+"#
    private static let wholeLineAdPattern = #"(?i)^(?:sync(?:ed)? by .+|resync(?:ed)? by .+|corrected by .+|subtitles by .+|www\.\S+\.\S+|https?://\S+|opensubtitles(?:\.org)?|subscene(?:\.com)?|addic7ed(?:\.com)?|support us.*|become vip.*|advertise your product.*)$"#
    private static let htmlTagPattern = #"</?[a-z][^>]*>"#

    public static func stripSubtitleAds(data: Data) -> Data {
        let text = decodeSRT(data: data).replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if blocks.isEmpty { return data }

        let adRegex = try? NSRegularExpression(pattern: adCuePattern, options: [])
        let wholeLineRegex = try? NSRegularExpression(pattern: wholeLineAdPattern, options: [])
        let tagRegex = try? NSRegularExpression(pattern: htmlTagPattern, options: .caseInsensitive)

        var kept: [(index: String, timestamp: String, text: String)] = []
        var removed = 0
        let boundary = 2

        for (i, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }
            let cueIndex = lines[0]
            let cueTimestamp = lines[1]
            let cueText = lines.dropFirst(2).joined(separator: "\n")
            let isBoundary = (i < boundary) || (i >= blocks.count - boundary)

            let plainLines = cueText.components(separatedBy: "\n").compactMap { ln -> String? in
                let stripped = tagRegex?.stringByReplacingMatches(in: ln, range: NSRange(ln.startIndex..., in: ln), withTemplate: "").trimmingCharacters(in: .whitespaces) ?? ln
                return stripped.isEmpty ? nil : stripped
            }

            let isPureAd = !plainLines.isEmpty && plainLines.allSatisfy { line in
                guard let match = wholeLineRegex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return false }
                return match.range.location != NSNotFound
            }

            let hasAdMatch: Bool = {
                guard let match = adRegex?.firstMatch(in: cueText, range: NSRange(cueText.startIndex..., in: cueText)) else { return false }
                return match.range.location != NSNotFound
            }()

            if (isBoundary && hasAdMatch) || isPureAd {
                removed += 1
                continue
            }
            kept.append((index: cueIndex, timestamp: cueTimestamp, text: cueText))
        }

        if removed == 0 {
            return data
        }

        AppLogger.info("Stripped \(removed) ad/credit cue(s) from subtitles.")
        var outBlocks: [String] = []
        for (idx, item) in kept.enumerated() {
            outBlocks.append("\(idx + 1)\n\(item.timestamp)\n\(item.text)")
        }
        let resultStr = outBlocks.joined(separator: "\n\n") + "\n"
        return encodeSRT(resultStr)
    }

    // MARK: - Formatting Tag Stripping

    private static let formatTagPattern = #"(?i)</?(?:i|b|u|font)(?:\s[^>]*)?>"#

    public static func stripSubtitleFormatting(data: Data) -> Data {
        let text = decodeSRT(data: data)
        guard let regex = try? NSRegularExpression(pattern: formatTagPattern, options: []) else { return data }
        let range = NSRange(text.startIndex..., in: text)
        if regex.firstMatch(in: text, range: range) == nil {
            return data
        }
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        AppLogger.info("Stripped italic/bold/underline/font styling tags from subtitles.")
        return encodeSRT(cleaned)
    }

    // MARK: - ALL-CAPS Normalization

    public static func normalizeSubtitleCase(data: Data) -> Data {
        let text = decodeSRT(data: data).replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if blocks.isEmpty { return data }

        var totalLetters = 0
        var upperLetters = 0

        for b in blocks {
            let lines = b.components(separatedBy: "\n")
            guard lines.count > 2 else { continue }
            let body = lines.dropFirst(2).joined(separator: "\n")
            for ch in body {
                if ch.isLetter {
                    totalLetters += 1
                    if ch.isUppercase {
                        upperLetters += 1
                    }
                }
            }
        }

        guard totalLetters > 0 else { return data }
        let ratio = Double(upperLetters) / Double(totalLetters)
        if ratio < 0.85 {
            return data
        }

        let standaloneIRegex = try? NSRegularExpression(pattern: #"\bi\b"#, options: [])

        func fixCueText(_ cue: String) -> String {
            var chars = Array(cue.lowercased())
            var capitalizeNext = true
            for i in 0..<chars.count {
                let c = chars[i]
                if capitalizeNext && c.isLetter {
                    chars[i] = Character(c.uppercased())
                    capitalizeNext = false
                } else if c == "." || c == "!" || c == "?" || c == "[" || c == "(" || c == "-" {
                    capitalizeNext = true
                }
            }
            var s = String(chars)
            if let ir = standaloneIRegex {
                s = ir.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "I")
            }
            return s
        }

        var outBlocks: [String] = []
        for b in blocks {
            let lines = b.components(separatedBy: "\n")
            if lines.count < 2 {
                outBlocks.append(b)
                continue
            }
            let idx = lines[0]
            let ts = lines[1]
            let cueText = lines.dropFirst(2).joined(separator: "\n")
            outBlocks.append("\(idx)\n\(ts)\n\(fixCueText(cueText))")
        }

        AppLogger.info("Converted ALL-CAPS subtitle (\(Int(ratio * 100))% uppercase) to sentence case.")
        let resultStr = outBlocks.joined(separator: "\n\n") + "\n"
        return encodeSRT(resultStr)
    }

    // MARK: - Timestamps

    public static func firstCueStartSeconds(data: Data) -> Double? {
        let text = decodeSRT(data: data)
        let pattern = #"(\d+):(\d+):(\d+),(\d+)\s*-->"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let rH = Range(match.range(at: 1), in: text),
              let rM = Range(match.range(at: 2), in: text),
              let rS = Range(match.range(at: 3), in: text),
              let rMs = Range(match.range(at: 4), in: text) else {
            return nil
        }
        let h = Double(text[rH]) ?? 0
        let m = Double(text[rM]) ?? 0
        let s = Double(text[rS]) ?? 0
        let ms = Double(text[rMs]) ?? 0
        return h * 3600 + m * 60 + s + ms / 1000.0
    }

    public static func lastCueEndSeconds(data: Data) -> Double? {
        let text = decodeSRT(data: data)
        let pattern = #"\d+:\d+:\d+,\d+\s*-->\s*(\d+):(\d+):(\d+),(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last,
              let rH = Range(last.range(at: 1), in: text),
              let rM = Range(last.range(at: 2), in: text),
              let rS = Range(last.range(at: 3), in: text),
              let rMs = Range(last.range(at: 4), in: text) else {
            return nil
        }
        let h = Double(text[rH]) ?? 0
        let m = Double(text[rM]) ?? 0
        let s = Double(text[rS]) ?? 0
        let ms = Double(text[rMs]) ?? 0
        return h * 3600 + m * 60 + s + ms / 1000.0
    }

    // MARK: - Duration Validation

    public static func durationMatches(
        srtData: Data,
        videoDuration: Double?,
        mediaType: String = "movie",
        checkStart: Bool = true
    ) -> Bool {
        guard let videoDuration = videoDuration,
              let lastCue = lastCueEndSeconds(data: srtData) else {
            return true
        }

        let maxAfter = 3.0 * 60.0
        let maxBefore = 20.0 * 60.0

        if lastCue > videoDuration + maxAfter {
            AppLogger.info("Subtitle's last cue (\(Int(lastCue))s) runs past the video's decoded end (\(Int(videoDuration))s) — likely a cut mismatch.")
            return false
        }

        if lastCue < videoDuration - maxBefore {
            AppLogger.info("Subtitle's last cue (\(Int(lastCue))s) ends too far before the video's decoded end (\(Int(videoDuration))s) — likely the wrong release.")
            return false
        }

        if checkStart {
            let leadInTolerance = (mediaType == "episode") ? 12.0 : 300.0
            if let firstCue = firstCueStartSeconds(data: srtData), firstCue > leadInTolerance {
                AppLogger.info("Subtitle's first cue doesn't start until \(Int(firstCue))s into the video (allowed \(Int(leadInTolerance))s) — likely missing opening dialogue.")
                return false
            }
        }

        return true
    }

    // MARK: - Synchronizers

    public func syncSubtitlesMovie(srtData: Data, mkvURL: URL) async -> Data {
        guard let ffsubsync = toolRegistry.ffsubsync,
              let ffmpeg = toolRegistry.ffmpeg else {
            AppLogger.warning("ffsubsync or ffmpeg not found, skipping sync.")
            return srtData
        }

        AppLogger.info("Syncing subtitle timing to audio (ffsubsync)…")
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let inSrt = tmpDir.appendingPathComponent("input.srt")
        let outSrt = tmpDir.appendingPathComponent("synced.srt")
        let audioMp3 = tmpDir.appendingPathComponent("audio.mp3")

        try? srtData.write(to: inSrt)

        let extract = try? await ProcessRunner.run(
            executable: ffmpeg,
            arguments: [
                "-i", mkvURL.path,
                "-map", "0:a:0",
                "-ac", "1",
                "-ar", "16000",
                "-b:a", "32k",
                "-y",
                audioMp3.path
            ],
            timeout: 300
        )

        guard let extractRes = extract, extractRes.isSuccess, FileManager.default.fileExists(atPath: audioMp3.path) else {
            AppLogger.warning("Audio extraction failed, using original subtitle timing.")
            return srtData
        }

        let syncRes = try? await ProcessRunner.run(
            executable: ffsubsync,
            arguments: [
                audioMp3.path,
                "-i", inSrt.path,
                "-o", outSrt.path
            ],
            timeout: 600
        )

        if let res = syncRes, res.isSuccess, let syncedData = try? Data(contentsOf: outSrt) {
            AppLogger.info("Subtitle sync complete.")
            return syncedData
        }

        AppLogger.warning("ffsubsync failed, using original timing.")
        return srtData
    }

    public func runAlass(srtData: Data, mkvURL: URL) async -> Data? {
        guard let alass = toolRegistry.alassCLI else {
            AppLogger.warning("alass-cli not found, skipping sync.")
            return nil
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let inSrt = tmpDir.appendingPathComponent("input.srt")
        let outSrt = tmpDir.appendingPathComponent("synced.srt")
        try? srtData.write(to: inSrt)

        let res = try? await ProcessRunner.run(
            executable: alass,
            arguments: [
                "-g",
                mkvURL.path,
                inSrt.path,
                outSrt.path
            ],
            timeout: 600
        )

        guard let r = res, r.isSuccess, let syncedData = try? Data(contentsOf: outSrt) else {
            return nil
        }

        let combined = r.stdout + r.stderr
        let blocks = Self.parseAlassBlocks(combined)
        if !blocks.isEmpty && Self.isDifferentCut(blocks: blocks) {
            let maxShift = blocks.map { abs($0.shift) }.max() ?? 0
            AppLogger.warning("alass needed a \(String(format: "%.1f", maxShift))s block shift across a large part of the subtitle (different cut) — keeping original timing.")
            return nil
        }

        if Self.hasNegativeTimestamps(syncedData) {
            AppLogger.warning("alass output has negative timestamps (scrambled) — using original timing.")
            return nil
        }

        return syncedData
    }

    public func syncSubtitlesTV(srtData: Data, mkvURL: URL, videoDuration: Double?, sourceType: SourceType) async -> Data {
        AppLogger.info("Syncing subtitle timing to video (alass\(sourceType == .dvd ? ", DVD mode" : ""))…")

        if let synced = await runAlass(srtData: srtData, mkvURL: mkvURL) {
            if Self.durationMatches(srtData: synced, videoDuration: videoDuration, mediaType: "episode", checkStart: true) {
                AppLogger.info("Subtitle sync complete (alass).")
                return synced
            }
        }

        AppLogger.warning("alass output failed validation — using original timing.")
        return srtData
    }

    // MARK: - Alass Cut Analysis Helpers

    public static func parseAlassBlocks(_ text: String) -> [(count: Int, shift: Double)] {
        let pattern = #"shifted block of (\d+) subtitles with length [\d:\.]+ by ([+-]?\d+):(\d+):(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var out: [(count: Int, shift: Double)] = []

        for m in matches {
            guard let rCount = Range(m.range(at: 1), in: text),
                  let rH = Range(m.range(at: 2), in: text),
                  let rM = Range(m.range(at: 3), in: text),
                  let rS = Range(m.range(at: 4), in: text) else { continue }

            let count = Int(text[rCount]) ?? 0
            let hStr = String(text[rH])
            let sign: Double = hStr.hasPrefix("-") ? -1.0 : 1.0
            let h = abs(Double(hStr) ?? 0)
            let min = Double(text[rM]) ?? 0
            let s = Double(text[rS]) ?? 0

            let shift = sign * (h * 3600.0 + min * 60.0 + s)
            out.append((count: count, shift: shift))
        }

        return out
    }

    public static func isDifferentCut(blocks: [(count: Int, shift: Double)]) -> Bool {
        let total = blocks.reduce(0) { $0 + $1.count }
        guard total > 0 else { return false }
        let structuralShiftLimit = 15.0
        let cutFractionThreshold = 0.25

        return blocks.contains { (count, shift) in
            abs(shift) > structuralShiftLimit && (Double(count) / Double(total)) >= cutFractionThreshold
        }
    }

    public static func hasNegativeTimestamps(_ data: Data) -> Bool {
        let text = decodeSRT(data: data)
        let pattern = #"(?m)^\s*-\d+:\d+:\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
