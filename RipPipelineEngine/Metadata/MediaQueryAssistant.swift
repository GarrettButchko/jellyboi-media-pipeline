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

    /// Checks if a string is purely a generic disc rip track marker or placeholder with no title information.
    public static func isGenericTrackOrMarker(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let result = DiscRipRecognizer.analyze(fileURL: URL(fileURLWithPath: trimmed))
        return result.isDiscRip && result.suggestedTitle == nil
    }

    /// Reads a file stem and returns a clean OMDb search query, or nil when the
    /// on-device model is unavailable, times out, fails, or the filename is purely a generic track marker.
    public static func suggestSearchName(forFileNamed fileName: String) async -> MediaQuerySuggestion? {
        guard isAvailable else {
            logUnavailableOnce()
            return nil
        }

        let stem = (fileName as NSString).deletingPathExtension
        if isGenericTrackOrMarker(stem) {
            AppLogger.debug("Filename '\(fileName)' is a generic disc track marker with no title — skipping AI search query generation.")
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

    /// Uses the on-device model to inspect a disc rip file and its parent folder context,
    /// returning multiple plausible candidate titles (e.g. movies, sequels, or series names).
    public static func suggestDiscRipCandidates(fileName: String, parentFolder: String? = nil) async -> [String] {
        guard isAvailable else {
            logUnavailableOnce()
            return []
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let result = await withTimeout(seconds: generationTimeout) {
                await generateCandidates(fileName: fileName, parentFolder: parentFolder)
            }
            return result ?? []
        }
        #endif

        return []
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
            guard !title.isEmpty, !isGenericTrackOrMarker(title) else { return nil }

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
    private static func generateCandidates(fileName: String, parentFolder: String?) async -> [String]? {
        let session = LanguageModelSession(instructions: candidateInstructions)

        do {
            let response = try await session.respond(
                to: candidatePrompt(fileName: fileName, parentFolder: parentFolder),
                generating: GeneratedCandidatesList.self
            )

            var titles: [String] = []
            for raw in response.content.titles {
                let cleaned = cleanTitle(raw)
                if !cleaned.isEmpty && !isGenericTrackOrMarker(cleaned) && !titles.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) {
                    titles.append(cleaned)
                }
            }
            return titles.isEmpty ? nil : titles
        } catch {
            AppLogger.debug("On-device model candidates generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    @available(macOS 26.0, *)
    private static let candidateInstructions = """
    You are an expert film and television media classifier.
    Given a raw disc rip file name and an optional parent folder name, identify 1 to 5 plausible clean titles (movies, TV series, or franchise titles) that this disc rip represents.
    
    Rules:
    - Return clean, recognizable movie or TV series titles with official punctuation and spelling.
    - If the name points to a franchise, provide the main film, well-known sequels, or related installments.
    - Omit technical rip noise, track markers (e.g. t00, VTS, m2ts), resolution, and codec tags.
    - If the input is completely generic with no clues (e.g. "title_t00.mkv" in generic folder), return an empty list.
    """

    @available(macOS 26.0, *)
    private static func candidatePrompt(fileName: String, parentFolder: String?) -> String {
        var str = "File name: \"\(fileName)\""
        if let parent = parentFolder, !parent.isEmpty {
            str += "\nParent folder: \"\(parent)\""
        }
        str += """
        
        Examples:
        - File: "LOTR_FOTR_EE_D1_t00.mkv", Parent: "Rips" -> ["The Lord of the Rings: The Fellowship of the Ring", "The Lord of the Rings: The Two Towers", "The Lord of the Rings: The Return of the King"]
        - File: "title_t00.mkv", Parent: "THE_DARK_KNIGHT" -> ["The Dark Knight", "The Dark Knight Rises", "Batman Begins"]
        - File: "BREAKING_BAD_S1_D1_t00.mkv" -> ["Breaking Bad"]
        - File: "title_t00.mkv", Parent: "Downloads" -> []
        """
        return str
    }

    @available(macOS 26.0, *)
    private static let instructions = """
    You clean video file names into accurate movie or TV series search queries.

    Rules:
    - Extract the official movie or TV series title only. Never include episode titles, track markers, or quality tags.
    - If the input is a raw disc rip track marker, stream index, or generic placeholder (such as "t_110", "title_t00", "VTS_01_1", "00001", "track01", "disc1") with no identifiable movie or show title, do NOT guess, invent, or hallucinate a title. Return an empty title "", year 0, season 0, episode 0, and isTVEpisode false.
    - NEVER borrow or hallucinate titles, seasons, or episodes from examples or instructions. Only extract information that is explicitly stated in the input file name.
    - Fix obvious spelling mistakes in well-known titles (for example, "Severence" -> "Severance").
    - Remove quality, source, codec, audio, edition, and release-group tags (e.g. 1080p, BluRay, x264, HDR, Remux, DTS, AAC, PROPER, REPACK).
    - Keep official punctuation belonging to the media title (e.g. apostrophes, hyphens, colons, ampersands).
    - Move season and episode numbers out of the title into the season and episode fields.
    - Use 0 for an unknown year, season, or episode.
    - Set isTVEpisode to true ONLY when season and episode numbers or TV episode indicators are clearly present.
    """

    @available(macOS 26.0, *)
    private static func prompt(for fileName: String) -> String {
        """
        Extract the media title, year, season, and episode from the following file name.

        Examples:
        - "The.Matrix.1999.1080p.BluRay.x264-GROUP" -> title: "The Matrix", year: 1999, season: 0, episode: 0, isTVEpisode: false
        - "Breaking.Bad.S02E04.720p.HDTV.x264" -> title: "Breaking Bad", year: 0, season: 2, episode: 4, isTVEpisode: true
        - "Stranger Things 1x03 1080p NF WEBRip" -> title: "Stranger Things", year: 0, season: 1, episode: 3, isTVEpisode: true
        - "THE_DARK_KNIGHT_t00" -> title: "The Dark Knight", year: 0, season: 0, episode: 0, isTVEpisode: false
        - "t_110" -> title: "", year: 0, season: 0, episode: 0, isTVEpisode: false
        - "title_t00" -> title: "", year: 0, season: 0, episode: 0, isTVEpisode: false
        - "00001" -> title: "", year: 0, season: 0, episode: 0, isTVEpisode: false
        - "VTS_01_1" -> title: "", year: 0, season: 0, episode: 0, isTVEpisode: false

        Input:
        File name: "\(fileName)"
        """
    }

    @available(macOS 26.0, *)
    private static func cleanTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}"))
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-"))
        return title
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedMediaQuery {
        @Guide(description: "The clean movie or TV series title for an IMDb search, without the year or release tags. Empty string \"\" if the filename is a generic disc rip, track marker (e.g. t_110, title_t00), or has no recognizable title.")
        var title: String

        @Guide(description: "Four-digit release year, or 0 when unknown.")
        var year: Int

        @Guide(description: "Season number when this is a TV episode, otherwise 0.")
        var season: Int

        @Guide(description: "Episode number when this is a TV episode, otherwise 0.")
        var episode: Int

        @Guide(description: "True only when the file name clearly identifies a TV episode.")
        var isTVEpisode: Bool
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedCandidatesList {
        @Guide(description: "List of 1 to 5 plausible clean media titles.")
        var titles: [String]
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
