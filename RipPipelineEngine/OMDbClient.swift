import Foundation
import LoggingKit

public struct OMDbClient: Sendable {
    public let apiKey: String
    public let baseURL: URL
    public let session: URLSession
    public let customEpisodeOverrides: [String: (title: String, imdbId: String)]

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://www.omdbapi.com/")!,
        customEpisodeOverrides: [String: (title: String, imdbId: String)] = [:],
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.customEpisodeOverrides = customEpisodeOverrides
        self.session = session
    }

    // MARK: - Search Candidate Model

    public struct Candidate: Sendable {
        public let title: String
        public let year: String
        public let imdbId: String
        public let type: String
        public let votes: Int
        public let runtimeMinutes: Int?

        public var yearInt: Int? {
            let digits = year.prefix(4)
            return Int(digits)
        }
    }

    // MARK: - Single Exact Lookup

    public func lookup(title: String, year: Int? = nil, type: String? = nil) async -> MovieMatch? {
        var queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "t", value: title)
        ]
        if let year = year {
            queryItems.append(URLQueryItem(name: "y", value: String(year)))
        }
        if let type = type {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }

        guard let json = await fetchJSON(queryItems: queryItems),
              let response = json["Response"] as? String, response == "True",
              let imdbId = json["imdbID"] as? String,
              let matchedTitle = json["Title"] as? String,
              let matchedYearStr = json["Year"] as? String else {
            return nil
        }

        return MovieMatch(
            title: matchedTitle,
            year: matchedYearStr,
            imdbId: imdbId,
            votes: parseVotes(json["imdbVotes"] as? String),
            runtimeMinutes: parseRuntime(json["Runtime"] as? String)
        )
    }

    // MARK: - Search Candidates

    public func search(title: String, year: Int? = nil, type: String? = nil) async -> [Candidate] {
        var queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "s", value: title)
        ]
        if let year = year {
            queryItems.append(URLQueryItem(name: "y", value: String(year)))
        }
        if let type = type {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }

        guard let json = await fetchJSON(queryItems: queryItems),
              let response = json["Response"] as? String, response == "True",
              let searchList = json["Search"] as? [[String: Any]] else {
            return []
        }

        // Fetch details for top 5 candidates to obtain runtime & vote count
        var candidates: [Candidate] = []
        for item in searchList.prefix(5) {
            guard let imdbId = item["imdbID"] as? String,
                  let itemTitle = item["Title"] as? String,
                  let itemYear = item["Year"] as? String,
                  let itemType = item["Type"] as? String else { continue }

            var votes = 0
            var runtime: Int? = nil

            if let details = await fetchDetails(imdbId: imdbId) {
                votes = parseVotes(details["imdbVotes"] as? String)
                runtime = parseRuntime(details["Runtime"] as? String)
            }

            candidates.append(Candidate(
                title: itemTitle,
                year: itemYear,
                imdbId: imdbId,
                type: itemType,
                votes: votes,
                runtimeMinutes: runtime
            ))
        }

        return candidates
    }

    public func fetchDetails(imdbId: String) async -> [String: Any]? {
        let queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbId)
        ]
        return await fetchJSON(queryItems: queryItems)
    }

    // MARK: - Series & TV Episode Lookup

    public func lookupSeries(title: String) async -> (title: String, year: String, imdbId: String)? {
        let variations = TitleSanitizer.searchVariations(for: title)

        for query in variations {
            if let match = await lookup(title: query, type: "series") {
                return (match.title, match.year, match.imdbId)
            }
        }

        for query in variations {
            let candidates = await search(title: query, type: "series")
            if let best = candidates.max(by: { $0.votes < $1.votes }) {
                return (best.title, best.year, best.imdbId)
            }
        }

        return nil
    }

    public func lookupEpisode(
        seriesTitle: String,
        seriesYear: String,
        seriesImdbId: String,
        season: Int,
        episode: Int
    ) async -> TVEpisodeMatch? {
        let key = "\(seriesImdbId)_\(season)_\(episode)"
        if let override = customEpisodeOverrides[key] {
            AppLogger.info("Using custom episode override for \(key): \(override.title) [\(override.imdbId)]")
            return TVEpisodeMatch(
                seriesTitle: seriesTitle,
                seriesYear: seriesYear,
                seriesImdbId: seriesImdbId,
                season: season,
                episode: episode,
                episodeTitle: override.title,
                episodeImdbId: override.imdbId
            )
        }

        let queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: seriesImdbId),
            URLQueryItem(name: "Season", value: String(season)),
            URLQueryItem(name: "Episode", value: String(episode))
        ]

        if let json = await fetchJSON(queryItems: queryItems),
           let response = json["Response"] as? String, response == "True",
           let title = json["Title"] as? String,
           let epImdbId = json["imdbID"] as? String {
            return TVEpisodeMatch(
                seriesTitle: seriesTitle,
                seriesYear: seriesYear,
                seriesImdbId: seriesImdbId,
                season: season,
                episode: episode,
                episodeTitle: title,
                episodeImdbId: epImdbId
            )
        }

        // Fallback: Query season episode list if direct S/E query misses
        let seasonQueryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: seriesImdbId),
            URLQueryItem(name: "Season", value: String(season))
        ]
        if let seasonJson = await fetchJSON(queryItems: seasonQueryItems),
           let episodes = seasonJson["Episodes"] as? [[String: Any]] {
            for ep in episodes {
                if let epNumStr = ep["Episode"] as? String,
                   let epNum = Int(epNumStr), epNum == episode,
                   let epTitle = ep["Title"] as? String,
                   let epId = ep["imdbID"] as? String {
                    return TVEpisodeMatch(
                        seriesTitle: seriesTitle,
                        seriesYear: seriesYear,
                        seriesImdbId: seriesImdbId,
                        season: season,
                        episode: episode,
                        episodeTitle: epTitle,
                        episodeImdbId: epId
                    )
                }
            }
        }

        return nil
    }

    // MARK: - Multi-Stage General-Purpose Resolver

    public func resolveMovie(
        title: String,
        yearHint: String?,
        durationMinutes: Double?,
        inspector: MediaInspector? = nil,
        fileURL: URL? = nil
    ) async -> MovieMatch? {
        let variations = TitleSanitizer.searchVariations(for: title)
        let yearInt = yearHint != nil ? Int(yearHint!) : nil
        let durationMinInt = durationMinutes != nil ? Int(round(durationMinutes!)) : nil

        for query in variations {
            // Stage 1: Exact lookup with year hint if present
            if let year = yearInt {
                if let match = await lookup(title: query, year: year, type: "movie") {
                    AppLogger.info("OMDb (exact + year): \(match.title) (\(match.year)) [\(match.imdbId)]")
                    return match
                }
            }

            // Stage 2: Exact lookup without year hint
            if let match = await lookup(title: query, type: "movie") {
                AppLogger.info("OMDb (exact): \(match.title) (\(match.year)) [\(match.imdbId)]")
                return match
            }

            // Stage 3: Search candidates with year hint
            if let year = yearInt {
                let candidates = await search(title: query, year: year, type: "movie")
                if let best = await pickBestCandidate(
                    candidates,
                    durationMinutes: durationMinInt,
                    yearHint: year,
                    inspector: inspector,
                    fileURL: fileURL
                ) {
                    AppLogger.info("OMDb (search + year): \(best.title) (\(best.year)) [\(best.imdbId)] votes=\(best.votes)")
                    return MovieMatch(
                        title: best.title,
                        year: best.year,
                        imdbId: best.imdbId,
                        votes: best.votes,
                        runtimeMinutes: best.runtimeMinutes
                    )
                }
            }

            // Stage 4: Broad search candidates
            let broadCandidates = await search(title: query, type: "movie")
            if let best = await pickBestCandidate(
                broadCandidates,
                durationMinutes: durationMinInt,
                yearHint: yearInt,
                inspector: inspector,
                fileURL: fileURL
            ) {
                AppLogger.info("OMDb (search): \(best.title) (\(best.year)) [\(best.imdbId)] votes=\(best.votes) runtime=\(best.runtimeMinutes ?? 0)")
                return MovieMatch(
                    title: best.title,
                    year: best.year,
                    imdbId: best.imdbId,
                    votes: best.votes,
                    runtimeMinutes: best.runtimeMinutes
                )
            }
        }

        return nil
    }

    // MARK: - Candidate Disambiguation

    private func pickBestCandidate(
        _ candidates: [Candidate],
        durationMinutes: Int?,
        yearHint: Int?,
        inspector: MediaInspector?,
        fileURL: URL?
    ) async -> Candidate? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates.first }

        var targetDuration = durationMinutes
        if targetDuration == nil, let inspector = inspector, let fileURL = fileURL {
            if let decodedSec = try? await inspector.getDecodedDuration(fileURL: fileURL) {
                targetDuration = Int(round(decodedSec / 60.0))
            }
        }

        // If target duration is known, filter candidates within 30 minutes runtime
        if let target = targetDuration {
            let matched = candidates.filter { c in
                guard let rt = c.runtimeMinutes else { return false }
                return abs(rt - target) <= 30
            }
            if !matched.isEmpty {
                return matched.max(by: { $0.votes < $1.votes })
            }
        }

        // Year proximity disambiguation
        if let year = yearHint {
            let exactYear = candidates.filter { $0.yearInt == year }
            if !exactYear.isEmpty {
                return exactYear.max(by: { $0.votes < $1.votes })
            }
        }

        return candidates.max(by: { $0.votes < $1.votes })
    }

    // MARK: - HTTP Network Request with Retry

    private func fetchJSON(queryItems: [URLQueryItem], maxRetries: Int = 3) async -> [String: Any]? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        components?.queryItems = queryItems
        guard let url = components?.url else { return nil }

        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        return obj
                    }
                }
            } catch {
                if attempt == maxRetries {
                    AppLogger.error("OMDb request failed after \(maxRetries) attempts: \(error.localizedDescription)")
                }
            }
            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
            }
        }

        return nil
    }

    // MARK: - Value Parsing

    private func parseVotes(_ s: String?) -> Int {
        guard let s = s else { return 0 }
        let clean = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Int(clean) ?? 0
    }

    private func parseRuntime(_ s: String?) -> Int? {
        guard let s = s else { return nil }
        let digits = s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits)
    }
}
