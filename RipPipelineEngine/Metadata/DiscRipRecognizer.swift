import Foundation

public enum DiscRipReason: String, Sendable {
    case genericMakeMKV = "Generic MakeMKV track filename (e.g. title_t00)"
    case rawDiscTrack = "Disc volume label with track suffix (e.g. DISC_NAME_t00)"
    case dvdStream = "Raw DVD stream filename (e.g. VTS_01_1)"
    case blurayStream = "Raw Blu-ray stream number (e.g. 00001 or 00800)"
    case genericDiscLabel = "Generic disc placeholder (e.g. DVD, DISC1, UNTITLED)"
    case emptyOrGenericMetadata = "Missing or generic disc metadata"

    public var userExplanation: String {
        switch self {
        case .genericMakeMKV:
            return "This file uses MakeMKV's default generic track naming (title_t00). A movie or TV title is needed to match IMDb."
        case .rawDiscTrack:
            return "This file contains a raw disc volume label and track number. Providing an accurate title ensures exact metadata matching."
        case .dvdStream:
            return "This file appears to be a raw DVD VTS rip. Enter the actual movie or TV title."
        case .blurayStream:
            return "This file uses a raw Blu-ray stream number. Enter the actual movie or TV title."
        case .genericDiscLabel:
            return "This file uses a generic disc or track label. Enter the actual movie or TV title."
        case .emptyOrGenericMetadata:
            return "No recognizable movie or TV title could be detected from the disc. Please provide the title."
        }
    }
}

public struct DiscRipDetectionResult: Sendable {
    public let isDiscRip: Bool
    public let reason: DiscRipReason?
    public let suggestedTitle: String?

    public init(isDiscRip: Bool, reason: DiscRipReason? = nil, suggestedTitle: String? = nil) {
        self.isDiscRip = isDiscRip
        self.reason = reason
        self.suggestedTitle = suggestedTitle
    }
}

/// Detects whether an MKV video file is a raw rip straight from a physical disc
public struct DiscRipRecognizer: Sendable {

    // Regex for MakeMKV generic track: title_t00, title00, t00, t_110, track_01, etc.
    private static let genericMakeMKVRegex = try? NSRegularExpression(
        pattern: #"^(?:(?:title|track)[._-]?)?[tT][._-]?\d{1,3}$|^(?:title|track)[._-]?\d{1,3}$"#,
        options: .caseInsensitive
    )

    // Regex for MakeMKV disc volume with track suffix: e.g. THE_MATRIX_t00, THE_MATRIX_t_110, AVATAR_DISC1_t01
    private static let discWithTrackRegex = try? NSRegularExpression(
        pattern: #"^(.*?)[._-][tT][._-]?\d{1,3}$"#,
        options: .caseInsensitive
    )

    // Regex for DVD VTS rips: VTS_01_1, VTS_02_0, etc.
    private static let dvdVtsRegex = try? NSRegularExpression(
        pattern: #"^vts[._-]?\d{1,2}[._-]?\d{1,2}$"#,
        options: .caseInsensitive
    )

    // Regex for Blu-ray M2TS stream numbers: 00000, 00001, 00800, etc.
    private static let blurayStreamRegex = try? NSRegularExpression(
        pattern: #"^\d{4,6}$"#,
        options: []
    )

    // Generic placeholders
    public static let genericNames: Set<String> = [
        "dvd", "dvd_video", "dvdvideo", "video_ts", "videots",
        "bdmv", "bluray", "blu_ray", "untitled", "unknown",
        "movie", "disc", "disk", "cd", "track", "no_name"
    ]

    // Disc volume generic labels: DISC_1, DISK1, BD_1, DVD_1, etc.
    private static let discIndexRegex = try? NSRegularExpression(
        pattern: #"^(?:disc|disk|cd|bd|dvd|track|title)[._-]?\d{1,3}$"#,
        options: .caseInsensitive
    )

    /// Inspect a file URL and its raw title string to determine if it is straight from a disc
    public static func analyze(fileURL: URL, rawMetadataTitle: String? = nil) -> DiscRipDetectionResult {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let trimmedStem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerStem = trimmedStem.lowercased()

        // 1-4. Check generic disc patterns and labels (MakeMKV, DVD VTS, Blu-ray streams, generic words/labels)
        let stemRange = NSRange(trimmedStem.startIndex..., in: trimmedStem)
        let matchedReason: DiscRipReason? = {
            if genericMakeMKVRegex?.firstMatch(in: trimmedStem, range: stemRange) != nil {
                return .genericMakeMKV
            }
            if dvdVtsRegex?.firstMatch(in: trimmedStem, range: stemRange) != nil {
                return .dvdStream
            }
            if blurayStreamRegex?.firstMatch(in: trimmedStem, range: stemRange) != nil {
                return .blurayStream
            }
            if genericNames.contains(lowerStem) || discIndexRegex?.firstMatch(in: trimmedStem, range: stemRange) != nil {
                return .genericDiscLabel
            }
            return nil
        }()

        if let matchedReason {
            let parentHint = suggestedTitleFromParent(fileURL: fileURL)
            return DiscRipDetectionResult(
                isDiscRip: true,
                reason: matchedReason,
                suggestedTitle: parentHint
            )
        }

        // 5. Check MakeMKV disc volume with track suffix: e.g. THE_MATRIX_t00, B1_D1_t00
        if let regex = discWithTrackRegex,
           let match = regex.firstMatch(in: trimmedStem, range: NSRange(trimmedStem.startIndex..., in: trimmedStem)),
           let r1 = Range(match.range(at: 1), in: trimmedStem) {
            let prefix = String(trimmedStem[r1])
            let cleanedSuggestion = cleanSuggestedDiscTitle(prefix)

            // If the prefix itself is a generic word like "DISC1" or "title"
            if genericNames.contains(cleanedSuggestion.lowercased()) ||
               (discIndexRegex?.firstMatch(in: cleanedSuggestion, range: NSRange(cleanedSuggestion.startIndex..., in: cleanedSuggestion)) != nil) {
                let parentHint = suggestedTitleFromParent(fileURL: fileURL)
                return DiscRipDetectionResult(
                    isDiscRip: true,
                    reason: .genericMakeMKV,
                    suggestedTitle: parentHint
                )
            }

            return DiscRipDetectionResult(
                isDiscRip: true,
                reason: .rawDiscTrack,
                suggestedTitle: cleanedSuggestion.isEmpty ? nil : cleanedSuggestion
            )
        }

        // 6. Check metadata title tag if present
        if let meta = rawMetadataTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !meta.isEmpty {
            let lowerMeta = meta.lowercased()
            if genericNames.contains(lowerMeta) ||
               (discIndexRegex?.firstMatch(in: meta, range: NSRange(meta.startIndex..., in: meta)) != nil) {
                let cleaned = cleanSuggestedDiscTitle(trimmedStem)
                let parentHint = suggestedTitleFromParent(fileURL: fileURL)
                return DiscRipDetectionResult(
                    isDiscRip: true,
                    reason: .emptyOrGenericMetadata,
                    suggestedTitle: cleaned.isEmpty ? parentHint : cleaned
                )
            }
        }

        return DiscRipDetectionResult(isDiscRip: false)
    }

    /// Attempts to extract a meaningful title hint from the parent directory
    public static func suggestedTitleFromParent(fileURL: URL) -> String? {
        let parentDir = fileURL.deletingLastPathComponent().lastPathComponent
        guard !parentDir.isEmpty, parentDir != "/" else { return nil }
        let lower = parentDir.lowercased()
        if genericNames.contains(lower) { return nil }
        if let regex = discIndexRegex, regex.firstMatch(in: parentDir, range: NSRange(parentDir.startIndex..., in: parentDir)) != nil {
            return nil
        }
        let cleaned = cleanSuggestedDiscTitle(parentDir)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Clean up raw volume names like "THE_LORD_OF_THE_RINGS_D1" into "The Lord of the Rings"
    public static func cleanSuggestedDiscTitle(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")

        // Strip trailing disc/part/disk tags
        let discRegex = try? NSRegularExpression(
            pattern: #"\s*(?:disc|disk|cd|part|side|d)[\s._-]*\d{1,2}\b"#,
            options: .caseInsensitive
        )
        if let r = discRegex {
            s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }

        // Collapse whitespace
        let words = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }

        // If all uppercase, convert to capitalized words
        if s == s.uppercased() {
            let minorWords: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "in", "nor", "of", "on", "or", "so", "the", "to", "up", "yet"]
            let titleCased = words.enumerated().map { (idx, w) -> String in
                let lower = w.lowercased()
                if idx > 0 && minorWords.contains(lower) {
                    return lower
                }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }.joined(separator: " ")
            return titleCased
        }

        return words.joined(separator: " ")
    }
}
