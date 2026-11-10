import Foundation

/// Interface for requesting user interaction during pipeline execution
public protocol PipelinePromptProvider: Sendable {
    /// Asks the user to provide or confirm an accurate name for a file straight from a disc
    /// - Parameters:
    ///   - fileURL: The URL of the MKV file being processed
    ///   - suggestedTitle: An optional heuristic title inferred from the volume label
    ///   - candidates: Optional AI or heuristic candidate titles to pick from
    ///   - reason: Why the file was flagged as straight from the disc
    /// - Returns: A user-provided title (e.g. "Inception (2010)" or "Breaking Bad S01E01"), or nil if skipped/cancelled
    func promptForTitle(
        fileURL: URL,
        suggestedTitle: String?,
        candidates: [String],
        reason: DiscRipReason
    ) async -> String?

    /// Asks the user to choose among candidate matches from OMDb when search is ambiguous
    func promptForTitleDisambiguation(
        fileURL: URL,
        originalQuery: String,
        candidates: [OMDbClient.Candidate]
    ) async -> OMDbClient.Candidate?

    /// Asks the user to choose an alternative subtitle when no subtitles matched their active restrictions
    func promptForSubtitleSelection(
        fileURL: URL,
        mediaTitle: String,
        candidates: [SubtitleCandidate]
    ) async -> SubtitleCandidate?
}

public typealias TitlePromptProvider = PipelinePromptProvider

public extension PipelinePromptProvider {
    func promptForTitle(
        fileURL: URL,
        suggestedTitle: String?,
        reason: DiscRipReason
    ) async -> String? {
        await promptForTitle(fileURL: fileURL, suggestedTitle: suggestedTitle, candidates: [], reason: reason)
    }

    func promptForTitleDisambiguation(
        fileURL: URL,
        originalQuery: String,
        candidates: [OMDbClient.Candidate]
    ) async -> OMDbClient.Candidate? {
        return nil
    }

    func promptForSubtitleSelection(
        fileURL: URL,
        mediaTitle: String,
        candidates: [SubtitleCandidate]
    ) async -> SubtitleCandidate? {
        return nil
    }
}

/// Command-line interactive prompt implementation
public struct CLITitlePromptProvider: PipelinePromptProvider {
    public static let shared = CLITitlePromptProvider()

    public init() {}

    public func promptForTitle(
        fileURL: URL,
        suggestedTitle: String?,
        candidates: [String],
        reason: DiscRipReason
    ) async -> String? {
        let isTerminal = isatty(STDIN_FILENO) != 0
        guard isTerminal else {
            // Non-interactive CLI: return suggestion or first candidate if available
            return candidates.first ?? suggestedTitle
        }

        print("\n" + String(repeating: "=", count: 65))
        print("💿  RAW DISC RIP DETECTED: \(fileURL.lastPathComponent)")
        print("    \(reason.userExplanation)")

        if !candidates.isEmpty {
            print("    Candidate titles found:")
            for (idx, cand) in candidates.enumerated() {
                print("    [\(idx + 1)] \(cand)")
            }
            print("    Press [1-\(candidates.count)] to pick, or type the accurate title.")
        } else if let suggested = suggestedTitle, !suggested.isEmpty {
            print("    Suggested Title: '\(suggested)'")
            print("    Press [Enter] to accept suggestion, or type the accurate title.")
        } else {
            print("    Please enter the movie or TV show title.")
            print("    Examples: 'The Matrix (1999)' or 'Breaking Bad S01E01'")
        }
        print(String(repeating: "-", count: 65))
        print("Enter title or choice number (or type 'skip' to use filename): ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return candidates.first ?? suggestedTitle
        }

        if input.isEmpty {
            return candidates.first ?? suggestedTitle
        }
        if input.lowercased() == "skip" {
            return nil
        }
        if let idx = Int(input), idx >= 1, idx <= candidates.count {
            return candidates[idx - 1]
        }

        return input
    }

    public func promptForTitle(
        fileURL: URL,
        suggestedTitle: String?,
        reason: DiscRipReason
    ) async -> String? {
        await promptForTitle(fileURL: fileURL, suggestedTitle: suggestedTitle, candidates: [], reason: reason)
    }

    public func promptForTitleDisambiguation(
        fileURL: URL,
        originalQuery: String,
        candidates: [OMDbClient.Candidate]
    ) async -> OMDbClient.Candidate? {
        let isTerminal = isatty(STDIN_FILENO) != 0
        guard isTerminal, !candidates.isEmpty else { return nil }

        print("\n" + String(repeating: "=", count: 65))
        print("🎬  AMBIGUOUS TITLE MATCH FOR: \(originalQuery)")
        print("    Closest IMDb titles:")
        for (i, cand) in candidates.prefix(5).enumerated() {
            let runtimeStr = cand.runtimeMinutes.map { "\($0) min" } ?? "Unknown runtime"
            let votesStr = cand.votes > 0 ? "\(cand.votes) votes" : "Few votes"
            print("    [\(i + 1)] \(cand.title) (\(cand.year)) [\(cand.type)] - \(runtimeStr), \(votesStr) (IMDb: https://www.imdb.com/title/\(cand.imdbId)/)")
        }
        print(String(repeating: "-", count: 65))
        print("Choose [1-\(min(5, candidates.count))] or press Enter to skip: ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let choice = Int(input),
              choice >= 1, choice <= min(5, candidates.count) else {
            return nil
        }

        return candidates[choice - 1]
    }

    public func promptForSubtitleSelection(
        fileURL: URL,
        mediaTitle: String,
        candidates: [SubtitleCandidate]
    ) async -> SubtitleCandidate? {
        let isTerminal = isatty(STDIN_FILENO) != 0
        guard isTerminal, !candidates.isEmpty else { return nil }

        print("\n" + String(repeating: "=", count: 65))
        print("💬  NO SUBTITLES MATCHED ACTIVE RESTRICTIONS: \(mediaTitle)")
        print("    Available alternative releases ranked by relevance:")
        for (i, cand) in candidates.prefix(6).enumerated() {
            let fpsStr = cand.fps.map { String(format: "%.3f fps", $0) } ?? "unknown fps"
            let tags = [
                cand.hearingImpaired ? "SDH" : nil,
                cand.isHDTV ? "HDTV" : nil,
                cand.isCommentary ? "Commentary" : nil
            ].compactMap { $0 }.joined(separator: ", ")
            let tagStr = tags.isEmpty ? "" : " [\(tags)]"
            let rejections = cand.rejectionReasons.isEmpty ? "" : " (Filtered: \(cand.rejectionReasons.joined(separator: "; ")))"
            print("    [\(i + 1)] \(cand.release) (\(cand.downloadCount) downloads, score: \(cand.score), \(fpsStr))\(tagStr)\(rejections)")
        }
        print(String(repeating: "-", count: 65))
        print("Choose [1-\(min(6, candidates.count))] to download anyway or press Enter to skip: ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let choice = Int(input),
              choice >= 1, choice <= min(6, candidates.count) else {
            return nil
        }

        return candidates[choice - 1]
    }
}
