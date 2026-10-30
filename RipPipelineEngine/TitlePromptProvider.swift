import Foundation

/// Interface for requesting an accurate media title from the user when a raw disc rip is detected
public protocol TitlePromptProvider: Sendable {
    /// Asks the user to provide or confirm an accurate name for a file straight from a disc
    /// - Parameters:
    ///   - fileURL: The URL of the MKV file being processed
    ///   - suggestedTitle: An optional heuristic title inferred from the volume label
    ///   - reason: Why the file was flagged as straight from the disc
    /// - Returns: A user-provided title (e.g. "Inception (2010)" or "Breaking Bad S01E01"), or nil if skipped/cancelled
    func promptForTitle(
        fileURL: URL,
        suggestedTitle: String?,
        reason: DiscRipReason
    ) async -> String?
}

/// Command-line interactive prompt implementation
public struct CLITitlePromptProvider: TitlePromptProvider {
    public static let shared = CLITitlePromptProvider()

    public init() {}

    public func promptForTitle(
        fileURL: URL,
        suggestedTitle: String?,
        reason: DiscRipReason
    ) async -> String? {
        let isTerminal = isatty(STDIN_FILENO) != 0
        guard isTerminal else {
            // Non-interactive CLI: return suggestion if available
            return suggestedTitle
        }

        print("\n" + String(repeating: "=", count: 65))
        print("📀  RAW DISC RIP DETECTED: \(fileURL.lastPathComponent)")
        print("    \(reason.userExplanation)")
        if let suggested = suggestedTitle, !suggested.isEmpty {
            print("    Suggested Title: '\(suggested)'")
            print("    Press [Enter] to accept suggestion, or type the accurate title.")
        } else {
            print("    Please enter the movie or TV show title.")
            print("    Examples: 'The Matrix (1999)' or 'Breaking Bad S01E01'")
        }
        print(String(repeating: "-", count: 65))
        print("Enter title (or type 'skip' to use filename): ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return suggestedTitle
        }

        if input.isEmpty {
            return suggestedTitle
        }
        if input.lowercased() == "skip" {
            return nil
        }

        return input
    }
}
