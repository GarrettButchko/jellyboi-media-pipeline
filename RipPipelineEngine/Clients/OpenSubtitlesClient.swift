import Foundation
import LoggingKit

public actor OpenSubtitlesClient {
    private let apiKey: String
    private let userAgent: String
    private let username: String
    private let password: String
    private let session: URLSession

    private var token: String? = nil
    private var downloadCache: [String: Data] = [:]

    private static let baseURL = "https://api.opensubtitles.com/api/v1"

    private static let blurayKeywords: Set<String> = ["bluray", "bdrip", "bdremux", "remux", "brrip", "uhd"]
    private static let dvdKeywords: Set<String> = ["dvdrip", "dvd", "dvdscr", "dvd5", "dvd9"]

    private static let stopwords: Set<String> = [
        "a", "about", "after", "all", "also", "am", "an", "and", "any", "are",
        "as", "at", "be", "because", "been", "but", "by", "can", "could",
        "did", "do", "does", "doing", "down", "for", "from", "get", "go",
        "going", "got", "had", "has", "have", "he", "her", "here", "him",
        "his", "how", "i", "if", "in", "into", "is", "it", "its", "just",
        "like", "me", "more", "my", "no", "not", "now", "of", "on", "one",
        "or", "our", "out", "over", "really", "right", "said", "say", "see",
        "she", "so", "some", "that", "the", "their", "them", "then", "there",
        "these", "they", "this", "to", "up", "us", "was", "we", "were",
        "what", "when", "where", "which", "who", "why", "will", "with",
        "would", "you", "your"
    ]

    public init(apiKey: String, userAgent: String, username: String, password: String) {
        self.apiKey = apiKey
        self.userAgent = userAgent
        self.username = username
        self.password = password

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    private func loginIfNeeded() async -> String? {
        if let token = self.token {
            return token
        }
        guard !username.isEmpty, !password.isEmpty else {
            return nil
        }

        guard let url = URL(string: "\(Self.baseURL)/login") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["username": username, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["token"] as? String {
                self.token = token
                AppLogger.info("OpenSubtitles: logged in as '\(username)' (higher download quota).")
                return token
            }
        } catch {
            AppLogger.warning("OpenSubtitles login failed (\(error.localizedDescription)) — falling back to anonymous quota.")
        }
        return nil
    }

    private func makeHeaders() async -> [String: String] {
        var h = [
            "Api-Key": apiKey,
            "User-Agent": userAgent,
            "Content-Type": "application/json"
        ]
        if let token = await loginIfNeeded() {
            h["Authorization"] = "Bearer \(token)"
        }
        return h
    }

    // MARK: - Search Subtitles

    public func fetchSubtitles(
        imdbId: String,
        sourceType: SourceType,
        mediaType: String = "movie",
        preferExtended: Bool = false,
        mkvURL: URL? = nil,
        videoDuration: Double? = nil,
        videoFPS: Double? = nil,
        processor: SubtitleProcessor,
        config: PipelineConfig = PipelineConfig.load(),
        promptProvider: PipelinePromptProvider? = nil,
        mediaTitle: String = ""
    ) async -> Data? {
        AppLogger.info("Fetching subtitles for \(imdbId) (source=\(sourceType.rawValue))...")
        guard !apiKey.isEmpty && apiKey != "YOUR_OS_KEY_HERE" else {
            AppLogger.warning("No OpenSubtitles API key configured.")
            return nil
        }

        let imdbNum = imdbId.hasPrefix("tt") ? String(imdbId.dropFirst(2)) : imdbId
        var urlComp = URLComponents(string: "\(Self.baseURL)/subtitles")
        let langCode = config.subtitleLanguage.isEmpty ? "en" : config.subtitleLanguage
        urlComp?.queryItems = [
            URLQueryItem(name: "imdb_id", value: imdbNum),
            URLQueryItem(name: "languages", value: langCode),
            URLQueryItem(name: "type", value: mediaType)
        ]
        guard let url = urlComp?.url else { return nil }

        let headers = await makeHeaders()
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            AppLogger.warning("OpenSubtitles search request failed.")
            return nil
        }

        let hdtvRegex = try? NSRegularExpression(pattern: #"\bhdtv\b"#, options: .caseInsensitive)
        let hiTagRegex = try? NSRegularExpression(pattern: #"\b(?:hi|sdh|pcc)\b"#, options: .caseInsensitive)
        let cutRegex = try? NSRegularExpression(pattern: #"extended|redux|director'?s cut|unrated|special edition"#, options: .caseInsensitive)

        var allCandidates: [SubtitleCandidate] = []
        var skippedFPS = 0
        var skippedHDTV = 0
        var skippedHI = 0
        var skippedCommentary = 0

        for item in items {
            guard let attrs = item["attributes"] as? [String: Any],
                  let files = attrs["files"] as? [[String: Any]],
                  let firstFile = files.first,
                  let fileIdNum = firstFile["file_id"] else {
                continue
            }

            let fileId = String(describing: fileIdNum)
            let release = (attrs["release"] as? String) ?? ""
            let releaseLower = release.lowercased()

            let subFPS = (attrs["fps"] as? Double) ?? 0.0
            let isHI = ((attrs["hearing_impaired"] as? Bool) ?? false) || (hiTagRegex?.firstMatch(in: releaseLower, range: NSRange(releaseLower.startIndex..., in: releaseLower)) != nil)
            let isHDTV = (hdtvRegex?.firstMatch(in: release, range: NSRange(release.startIndex..., in: release)) != nil) || releaseLower.contains("hdtv")
            let isCommentary = releaseLower.contains("commentary")
            let isCutVariant = (cutRegex?.firstMatch(in: releaseLower, range: NSRange(releaseLower.startIndex..., in: releaseLower)) != nil)

            var rejections: [String] = []

            if config.matchVideoFPS, let vFPS = videoFPS, subFPS > 0, abs(subFPS - vFPS) > 0.5 {
                rejections.append(String(format: "FPS mismatch (%.3f vs video %.3f)", subFPS, vFPS))
                skippedFPS += 1
            }

            if config.excludeHDTV && isHDTV {
                rejections.append("HDTV broadcast release (timing often contains commercial cuts)")
                skippedHDTV += 1
            }

            if config.excludeHearingImpaired && isHI {
                rejections.append("Hearing Impaired / SDH (closed captions)")
                skippedHI += 1
            }

            if config.excludeCommentary && isCommentary {
                rejections.append("Audio commentary subtitle")
                skippedCommentary += 1
            }

            if !preferExtended && !config.preferExtendedCuts && isCutVariant {
                rejections.append("Cut variant (extended / unrated / director's cut)")
            }

            let downloads = (attrs["download_count"] as? Int) ?? 0
            let score = scoreRelease(release: release, sourceType: sourceType, preferExtended: preferExtended || config.preferExtendedCuts)
            allCandidates.append(SubtitleCandidate(
                fileId: fileId,
                release: release,
                score: score,
                downloadCount: downloads,
                hearingImpaired: isHI,
                fps: subFPS > 0 ? subFPS : nil,
                isHDTV: isHDTV,
                isCommentary: isCommentary,
                isCutVariant: isCutVariant,
                rejectionReasons: rejections
            ))
        }

        if skippedFPS > 0 || skippedHDTV > 0 || skippedHI > 0 || skippedCommentary > 0 {
            AppLogger.info("OpenSubtitles: filtered out \(skippedFPS) fps-mismatch, \(skippedHDTV) HDTV, \(skippedHI) HI, \(skippedCommentary) commentary release(s).")
        }

        var eligibleCandidates = allCandidates.filter { $0.rejectionReasons.isEmpty }
        eligibleCandidates.sort { ($0.score, $0.downloadCount) > ($1.score, $1.downloadCount) }

        if !eligibleCandidates.isEmpty {
            let best = eligibleCandidates[0]
            AppLogger.info("OpenSubtitles: \(eligibleCandidates.count) eligible result(s), best score=\(best.score) release='\(best.release)'")

            let sourceKeywords = (sourceType == .bluray) ? Self.blurayKeywords : Self.dvdKeywords
            if !sourceKeywords.contains(where: { best.release.lowercased().contains($0) }) {
                AppLogger.info("No \(sourceType.rawValue)-tagged subtitle release available for this title — using best broadcast/web match instead.")
            }

            let references = config.enforceContentCheck ? await fetchReferenceTranscripts(candidates: eligibleCandidates, config: config) : []

            for cand in eligibleCandidates {
                guard let content = await downloadSubtitle(fileId: cand.fileId, release: cand.release, config: config) else {
                    continue
                }

                if config.enforceDurationCheck {
                    if await !SubtitleProcessor.durationMatches(srtData: content, videoDuration: videoDuration, mediaType: mediaType, checkStart: false) {
                        AppLogger.info("OpenSubtitles '\(cand.release)' (dl=\(cand.downloadCount)) failed duration check — trying next.")
                        continue
                    }
                }

                if config.enforceContentCheck && !references.isEmpty {
                    if !contentMatches(content: content, references: references) {
                        AppLogger.info("OpenSubtitles '\(cand.release)' (dl=\(cand.downloadCount)) failed content check — trying next.")
                        continue
                    }
                }

                if config.enforceStructuralAlignmentCheck, let mkvURL = mkvURL {
                    guard let synced = await processor.runAlass(srtData: content, mkvURL: mkvURL) else {
                        AppLogger.info("OpenSubtitles '\(cand.release)' (dl=\(cand.downloadCount)) failed alass alignment — trying next.")
                        continue
                    }
                    if await !SubtitleProcessor.durationMatches(srtData: synced, videoDuration: videoDuration, mediaType: mediaType, checkStart: true) {
                        AppLogger.info("OpenSubtitles '\(cand.release)' (dl=\(cand.downloadCount)) failed post-alignment duration check — trying next.")
                        continue
                    }
                }

                AppLogger.info("OpenSubtitles: selected '\(cand.release)' (score=\(cand.score) dl=\(cand.downloadCount))")
                return content
            }
        }

        AppLogger.warning("OpenSubtitles: no eligible candidate passed the duration/content/structure checks.")

        // Prompt user with ranked alternative fallback options if enabled
        if config.promptForSubtitleFallback, let promptProvider = promptProvider, !allCandidates.isEmpty {
            AppLogger.info("Prompting user with ranked alternative subtitle candidates...")
            let sortedCandidates = allCandidates.sorted { ($0.score, $0.downloadCount) > ($1.score, $1.downloadCount) }
            if let selected = await promptProvider.promptForSubtitleSelection(
                fileURL: mkvURL ?? URL(fileURLWithPath: ""),
                mediaTitle: mediaTitle.isEmpty ? imdbId : mediaTitle,
                candidates: sortedCandidates
            ) {
                AppLogger.info("User selected fallback subtitle candidate: '\(selected.release)'")
                if let content = await downloadSubtitle(fileId: selected.fileId, release: selected.release, config: config) {
                    return content
                }
            }
        }

        return nil
    }

    // MARK: - Scoring

    private func scoreRelease(release: String, sourceType: SourceType, preferExtended: Bool) -> Int {
        let nameLower = release.lowercased()
        let keywords = (sourceType == .bluray) ? Self.blurayKeywords : Self.dvdKeywords
        var score = keywords.contains(where: { nameLower.contains($0) }) ? 1 : 0

        if nameLower.contains("commentary") {
            score -= 3
        }

        let cutRegex = try? NSRegularExpression(pattern: #"extended|redux|director'?s cut|unrated|special edition"#, options: .caseInsensitive)
        if !preferExtended && cutRegex?.firstMatch(in: nameLower, range: NSRange(nameLower.startIndex..., in: nameLower)) != nil {
            score -= 2
        }

        return score
    }

    // MARK: - Download Subtitle

    private func downloadSubtitle(fileId: String, release: String, config: PipelineConfig = PipelineConfig.load()) async -> Data? {
        if let cached = downloadCache[fileId] {
            return cached
        }

        guard let url = URL(string: "\(Self.baseURL)/download") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let headers = await makeHeaders()
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let subFormat = config.subtitleFormat.isEmpty ? "srt" : config.subtitleFormat
        let body: [String: Any] = ["file_id": Int(fileId) ?? 0, "sub_format": subFormat]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let linkStr = json["link"] as? String,
                   let linkUrl = URL(string: linkStr) {
                    let (subData, subResp) = try await session.data(from: linkUrl)
                    if let subHttp = subResp as? HTTPURLResponse, subHttp.statusCode == 200 {
                        downloadCache[fileId] = subData
                        return subData
                    }
                }
            } catch {
                if attempt < 2 {
                    let wait = UInt64((attempt + 1) * 5)
                    AppLogger.warning("OpenSubtitles download attempt \(attempt + 1) failed — retrying in \(wait)s...")
                    try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                }
            }
        }

        AppLogger.warning("OpenSubtitles download failed for '\(release)'.")
        return nil
    }

    // MARK: - Content Dialogue Reference Check

    private func fetchReferenceTranscripts(candidates: [SubtitleCandidate], config: PipelineConfig) async -> [Data] {
        let ranked = candidates.sorted { $0.downloadCount > $1.downloadCount }
        let badTagRegex = try? NSRegularExpression(pattern: #"\b(?:hi|sdh|pcc|commentary)\b"#, options: .caseInsensitive)
        var refs: [Data] = []

        for cand in ranked {
            if badTagRegex?.firstMatch(in: cand.release, range: NSRange(cand.release.startIndex..., in: cand.release)) != nil {
                continue
            }
            if let data = await downloadSubtitle(fileId: cand.fileId, release: cand.release, config: config) {
                refs.append(data)
            }
            if refs.count >= 2 {
                break
            }
        }

        if !refs.isEmpty {
            AppLogger.info("OpenSubtitles: built dialogue reference from \(refs.count) release(s) for content verification.")
        }
        return refs
    }

    private func contentWordSet(srtData: Data) -> Set<String> {
        let text = SubtitleProcessor.decodeSRT(data: srtData)
        let tagRegex = try? NSRegularExpression(pattern: #"</?[a-z][^>]*>"#, options: .caseInsensitive)
        let bracketRegex = try? NSRegularExpression(pattern: #"[\\[\\(].*?[\\]\\)]"#, options: [])

        var cleaned = tagRegex?.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ") ?? text
        cleaned = bracketRegex?.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ") ?? cleaned

        let wordRegex = try? NSRegularExpression(pattern: #"[a-z0-9']+"#, options: .caseInsensitive)
        let matches = wordRegex?.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) ?? []

        var words = Set<String>()
        for m in matches {
            guard let r = Range(m.range, in: cleaned) else { continue }
            let w = String(cleaned[r]).lowercased()
            if !Self.stopwords.contains(w) {
                words.insert(w)
            }
        }
        return words
    }

    private func contentMatches(content: Data, references: [Data]) -> Bool {
        guard !references.isEmpty else { return true }
        let candWords = contentWordSet(srtData: content)
        guard !candWords.isEmpty else { return true }

        var bestSim = 0.0
        let threshold = 0.60

        for ref in references {
            let refWords = contentWordSet(srtData: ref)
            guard !refWords.isEmpty else { continue }
            let intersect = candWords.intersection(refWords).count
            let union = candWords.union(refWords).count
            let sim = Double(intersect) / Double(union)
            if sim > bestSim {
                bestSim = sim
            }
        }

        AppLogger.info("Subtitle content similarity vs reference: \(String(format: "%.2f", bestSim)) (threshold \(String(format: "%.2f", threshold)))")
        return bestSim >= threshold
    }
}
