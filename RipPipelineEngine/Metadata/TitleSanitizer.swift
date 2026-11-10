import Foundation

/// General-purpose title cleaner and query generator for movie and TV media files.
/// Free of hardcoded movie names, disc-specific hacks, or user-specific edge cases.
public struct TitleSanitizer: Sendable {

    // Scene & technical metadata tags commonly found in video filenames
    private static let sceneTagsPattern = #"""
    (?ix)\b(
        1080[pi]|720[pi]|2160[pi]|4k|uhd|bluray|blu-ray|bdrip|brrip|
        dvdrip|dvd|web-?dl|webrip|hdtv|remux|proper|repack|unrated|
        directors\.cut|extended(\.cut)?|theatrical|special\.edition|
        x264|x265|hevc|h\.?264|h\.?265|avc|vc-?1|mpeg-?2|xvid|divx|
        aac|ac3|dts(-?hd(\.ma)?)?|truehd|atmos|ddp?5\.1|eac3|pcm|flac|
        10bit|hdr(10(\+)?)?|dv|dolby\.vision|sdr
    )\b
    """#

    // Disc, disk, part, side indicators
    private static let discPartPattern = #"""
    (?ix)(
        [\(\[\{]?(?:disc|disk|cd|part|side)\s*[\dA-Z]+[\)\]\}]?|
        \b(?:disc|disk|cd|part|side)[\s._-]*[\dA-Z]+\b
    )
    """#

    // Release groups or website watermarks: [group], (group), -group, www.domain.com
    private static let releaseGroupPattern = #"""
    (?ix)(
        www\.[a-z0-9\-]+\.[a-z]{2,}|
        https?://\S+|
        \[[^\]]*\]|
        \{[^\}]*\}
    )
    """#

    // Trailing OCR/rip artifact numbers glued to words (e.g. "title7" -> "title")
    private static let gluedDigitsPattern = #"(?i)\b([a-zA-Z]{3,})\d{1,2}\b"#

    /// Clean a raw file stem or metadata title into a clean media title and optional year
    public static func sanitize(rawTitle: String) -> (title: String, year: Int?) {
        var text = rawTitle

        // 1. Extract year if present: (1999) or .1999. or [1999] or 1999
        var extractedYear: Int? = nil
        let yearRegex = try? NSRegularExpression(pattern: #"(?:[\(\[\s._-]|^)((?:19|20)\d{2})(?:[\)\]\s._-]|$)"#)
        if let match = yearRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text),
           let y = Int(text[r]) {
            extractedYear = y
            // Remove the year and everything following it from the title string if it looks like release metadata
            if let fullRange = Range(match.range, in: text) {
                text = String(text[..<fullRange.lowerBound])
            }
        }

        // 2. Remove release group watermarks and bracketed metadata
        if let r = try? NSRegularExpression(pattern: releaseGroupPattern) {
            text = r.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // 3. Remove scene technical tags
        if let r = try? NSRegularExpression(pattern: sceneTagsPattern) {
            text = r.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // 4. Remove disc/part indicators
        if let r = try? NSRegularExpression(pattern: discPartPattern) {
            text = r.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // 5. Replace separators (dots, underscores, dashes) with spaces
        text = text.replacingOccurrences(of: ".", with: " ")
        text = text.replacingOccurrences(of: "_", with: " ")

        // 6. Handle trailing digits attached to words
        if let r = try? NSRegularExpression(pattern: gluedDigitsPattern) {
            text = r.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
        }

        // 7. Normalize inverted "Title, The" -> "The Title"
        let invertedTheRegex = try? NSRegularExpression(pattern: #"^(.*?),\s*(The|A|An)$"#, options: .caseInsensitive)
        if let match = invertedTheRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(match.range(at: 1), in: text),
           let r2 = Range(match.range(at: 2), in: text) {
            text = "\(text[r2]) \(text[r1])"
        }

        // 8. Trim and collapse multiple spaces
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -:,._"))

        return (text, extractedYear)
    }

    /// Generates candidate search query variations for OMDb / metadata lookups.
    /// Eliminates need for hardcoding specific typos or movie titles.
    public static func searchVariations(for title: String) -> [String] {
        var variations: [String] = []

        func add(_ s: String) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !variations.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                variations.append(trimmed)
            }
        }

        let base = title.trimmingCharacters(in: .whitespacesAndNewlines)
        add(base)

        // 1. Accent / Diacritic folded variant (e.g., "Amélie" -> "Amelie")
        let folded = base.folding(options: .diacriticInsensitive, locale: .current)
        if folded != base {
            add(folded)
        }

        // 2. Ampersand variation ("&" <-> "and")
        if base.contains("&") {
            add(base.replacingOccurrences(of: "&", with: "and"))
        } else if base.localizedCaseInsensitiveContains(" and ") {
            add(base.replacingOccurrences(of: " and ", with: " & ", options: .caseInsensitive))
        }

        // 3. Punctuation-free variant (strips apostrophes, hyphens, colons, quotes)
        let noPunctuation = base
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        add(noPunctuation)

        // 4. Subtitle split: if title has ":" or " - ", try primary title
        if let colonIdx = base.firstIndex(of: ":") {
            let primary = String(base[..<colonIdx])
            add(primary)
        }
        if let dashRange = base.range(of: " - ") {
            let primary = String(base[..<dashRange.lowerBound])
            add(primary)
        }

        return variations
    }
}
