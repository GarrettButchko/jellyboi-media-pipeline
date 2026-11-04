import Foundation
import LoggingKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A cleaned OMDb search query produced from a raw media file name.
public struct MediaQuerySuggestion: Sendable, Equatable {
    public let searchTitle: String
    public let year: Int?
    public let season: Int?
    public let episode: Int?

    public init(searchTitle: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil) {
        self.searchTitle = searchTitle
        self.year = year
        self.season = season
        self.episode = episode
    }

    /// True only when the file name clearly identifies a TV episode.
    public var isTVEpisode: Bool {
        season != nil && episode != nil
    }
}

/// Uses Apple's on-device Foundation Models model to turn messy file names into
/// clean OMDb search queries. Everything is optional: callers must fall back to
/// their existing heuristics when `isAvailable` is false or generation fails.
public enum MediaQueryAssistant {

    public enum Availability: Sendable, Equatable {
        case available
        case unsupportedHardware
        case unsupportedOS
        case unavailable(String)
    }

    /// Maximum time to wait for the on-device model before falling back.
    private static let generationTimeout: TimeInterval = 20

    public static var availability: Availability {
        // Hard requirement: Apple Silicon. Intel Macs cannot run Apple Intelligence
        // models, so never even attempt to load the framework model there.
        guard HardwareInfo.isAppleSilicon else {
            return .unsupportedHardware
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                guard SystemLanguageModel.default.supportsLocale() else {
                    return .unavailable("current locale is not supported")
                }
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("device not eligible for Apple Intelligence")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Apple Intelligence is turned off")
                case .modelNotReady:
                    return .unavailable("on-device model is not ready")
                @unknown default:
                    return .unavailable("unknown availability reason")
                }
            @unknown default:
                return .unavailable("unknown availability state")
            }
        }
        #endif

        return .unsupportedOS
    }

    public static var isAvailable: Bool {
        availability == .available
    }

    /// Reads a file stem and returns a clean OMDb search query, or nil when the
    /// on-device model is unavailable, times out, or fails.
    public static func suggestSearchName(forFileNamed fileName: String) async -> MediaQuerySuggestion? {
        guard isAvailable else {
            logUnavailableOnce()
            return nil
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let result = await withTimeout(seconds: generationTimeout) {
                await generateSuggestion(for: fileName)
            }
            if result == nil {
                AppLogger.debug("On-device model returned no usable query — using heuristics.")
            }
            return result
        }
        #endif

        return nil
    }

    /// Logs the availability state once per process so batch runs don't spam.
    private static let loggedAvailability = LogOnce()

    private static func logUnavailableOnce() {
        loggedAvailability.run {
            switch availability {
            case .available:
                break
            case .unsupportedHardware:
                AppLogger.info("On-device AI name cleanup disabled — \(HardwareInfo.architecture) is not Apple Silicon.")
            case .unsupportedOS:
                AppLogger.info("On-device AI name cleanup disabled — requires macOS 26 or newer.")
            case .unavailable(let reason):
                AppLogger.info("On-device AI name cleanup disabled — \(reason).")
            }
        }
    }

    // MARK: - Generation

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func generateSuggestion(for fileName: String) async -> MediaQuerySuggestion? {
        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: prompt(for: fileName),
                generating: GeneratedMediaQuery.self
            )

            let generated = response.content
            let title = cleanTitle(generated.title)
            guard !title.isEmpty else { return nil }

            return MediaQuerySuggestion(
                searchTitle: title,
                year: (1900...2100).contains(generated.year) ? generated.year : nil,
                season: generated.season > 0 ? generated.season : nil,
                episode: generated.episode > 0 ? generated.episode : nil
            )
        } catch {
            AppLogger.debug("On-device model generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    @available(macOS 26.0, *)
    private static let instructions = """
    You clean video file names into IMDb search queries.

    Rules:
    - Return the movie or TV series title only, never the episode title.
    - Fix obvious spelling mistakes in well-known titles, for example "Pysch" means "Psych".
    - Remove quality, source, codec, audio, edition, and release-group tags.
    - Keep official punctuation such as apostrophes, colons, ampersands, and hyphens.
    - Move season and episode numbers out of the title into the season and episode fields.
    - Use 0 for an unknown year, season, or episode.
    - Set isTVEpisode to true only when the name identifies a TV episode.
    - Never invent a different title when the name is already clean.
    """

    @available(macOS 26.0, *)
    private static func prompt(for fileName: String) -> String {
        """
        File name: "\(fileName)"

        Examples:
        - "The.Matrix.1999.1080p.BluRay.x264-GROUP" -> title "The Matrix", year 1999, not a TV episode.
        - "Psych S2E9" -> title "Psych", season 2, episode 9, TV episode.
        - "Pysch S2E11 720p WEB-DL" -> title "Psych", season 2, episode 11, TV episode.
        """
    }

    @available(macOS 26.0, *)
    private static func cleanTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-"))
        return title
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedMediaQuery {
        @Guide(description: "The clean movie or TV series title for an IMDb search, without the year or release tags.")
        var title: String

        @Guide(description: "Four-digit release year, or 0 when unknown.")
        var year: Int

        @Guide(description: "Season number when this is a TV episode, otherwise 0.")
        var season: Int

        @Guide(description: "Episode number when this is a TV episode, otherwise 0.")
        var episode: Int

        @Guide(description: "True only when the file name identifies a TV episode.")
        var isTVEpisode: Bool
    }
    #endif

    // MARK: - Timeout

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

/// Small thread-safe once flag used to keep availability logging to one line.
private final class LogOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRun = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasRun else { return }
        hasRun = true
        body()
    }
}
