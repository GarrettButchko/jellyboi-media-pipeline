import Foundation

/// Configuration loaded from rip_pipeline.conf, Keychain, UserDefaults, or environment variables.
public struct PipelineConfig: Sendable {
    public var watchDir: URL
    public var libraryDir: URL
    public var tvLibraryDir: URL

    public var omdbKey: String
    public var openSubtitlesKey: String
    public var openSubtitlesUserAgent: String
    public var openSubtitlesUsername: String
    public var openSubtitlesPassword: String

    public var subtitleLanguage: String
    public var subtitleFormat: String

    // Subtitle retention & codec preferences
    public var subtitleRetentionMode: String // "englishOnly", "all", "custom"
    public var customSubtitleLanguages: String // e.g. "eng, en, und"
    public var keepSubRip: Bool
    public var keepAssSsa: Bool
    public var keepBitmapSubs: Bool
    public var preferEmbeddedSubs: Bool
    public var normalizeEmbeddedAllCaps: Bool
    public var clearDefaultSubtitleFlags: Bool

    // Subtitle restriction & filtering preferences
    public var excludeHDTV: Bool
    public var excludeHearingImpaired: Bool
    public var excludeCommentary: Bool
    public var preferExtendedCuts: Bool
    public var matchVideoFPS: Bool
    public var enforceDurationCheck: Bool
    public var enforceContentCheck: Bool
    public var enforceStructuralAlignmentCheck: Bool

    // Subtitle processing & sync
    public var stripSubtitleAds: Bool
    public var stripSubtitleFormatting: Bool
    public var normalizeSubtitleCase: Bool
    public var syncSubtitlesAudio: Bool

    // Interactive prompt preferences
    public var promptForSubtitleFallback: Bool
    public var promptForAmbiguousTitles: Bool

    // Jellyfin Direct Upload Configuration
    public var jellyfinServerURL: String
    public var jellyfinApiKey: String
    public var jellyfinUploadEnabled: Bool
    public var jellyfinMovieLibraryId: String
    public var jellyfinTvLibraryId: String
    public var jellyfinMovieServerPath: String
    public var jellyfinTvServerPath: String

    public init(
        watchDir: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Rips"),
        libraryDir: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Movies"),
        tvLibraryDir: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/TV Shows"),
        omdbKey: String = "",
        openSubtitlesKey: String = "",
        openSubtitlesUserAgent: String = "RipPipeline/1.0",
        openSubtitlesUsername: String = "",
        openSubtitlesPassword: String = "",
        subtitleLanguage: String = "en",
        subtitleFormat: String = "srt",
        subtitleRetentionMode: String = "englishOnly",
        customSubtitleLanguages: String = "eng, en, und",
        keepSubRip: Bool = true,
        keepAssSsa: Bool = true,
        keepBitmapSubs: Bool = true,
        preferEmbeddedSubs: Bool = true,
        normalizeEmbeddedAllCaps: Bool = true,
        clearDefaultSubtitleFlags: Bool = true,
        excludeHDTV: Bool = true,
        excludeHearingImpaired: Bool = true,
        excludeCommentary: Bool = true,
        preferExtendedCuts: Bool = false,
        matchVideoFPS: Bool = true,
        enforceDurationCheck: Bool = true,
        enforceContentCheck: Bool = true,
        enforceStructuralAlignmentCheck: Bool = true,
        stripSubtitleAds: Bool = true,
        stripSubtitleFormatting: Bool = true,
        normalizeSubtitleCase: Bool = true,
        syncSubtitlesAudio: Bool = true,
        promptForSubtitleFallback: Bool = true,
        promptForAmbiguousTitles: Bool = true,
        jellyfinServerURL: String = "",
        jellyfinApiKey: String = "",
        jellyfinUploadEnabled: Bool = false,
        jellyfinMovieLibraryId: String = "",
        jellyfinTvLibraryId: String = "",
        jellyfinMovieServerPath: String = "",
        jellyfinTvServerPath: String = ""
    ) {
        self.watchDir = watchDir
        self.libraryDir = libraryDir
        self.tvLibraryDir = tvLibraryDir
        self.omdbKey = omdbKey
        self.openSubtitlesKey = openSubtitlesKey
        self.openSubtitlesUserAgent = openSubtitlesUserAgent
        self.openSubtitlesUsername = openSubtitlesUsername
        self.openSubtitlesPassword = openSubtitlesPassword
        self.subtitleLanguage = subtitleLanguage
        self.subtitleFormat = subtitleFormat
        self.subtitleRetentionMode = subtitleRetentionMode
        self.customSubtitleLanguages = customSubtitleLanguages
        self.keepSubRip = keepSubRip
        self.keepAssSsa = keepAssSsa
        self.keepBitmapSubs = keepBitmapSubs
        self.preferEmbeddedSubs = preferEmbeddedSubs
        self.normalizeEmbeddedAllCaps = normalizeEmbeddedAllCaps
        self.clearDefaultSubtitleFlags = clearDefaultSubtitleFlags
        self.excludeHDTV = excludeHDTV
        self.excludeHearingImpaired = excludeHearingImpaired
        self.excludeCommentary = excludeCommentary
        self.preferExtendedCuts = preferExtendedCuts
        self.matchVideoFPS = matchVideoFPS
        self.enforceDurationCheck = enforceDurationCheck
        self.enforceContentCheck = enforceContentCheck
        self.enforceStructuralAlignmentCheck = enforceStructuralAlignmentCheck
        self.stripSubtitleAds = stripSubtitleAds
        self.stripSubtitleFormatting = stripSubtitleFormatting
        self.normalizeSubtitleCase = normalizeSubtitleCase
        self.syncSubtitlesAudio = syncSubtitlesAudio
        self.promptForSubtitleFallback = promptForSubtitleFallback
        self.promptForAmbiguousTitles = promptForAmbiguousTitles
        self.jellyfinServerURL = jellyfinServerURL
        self.jellyfinApiKey = jellyfinApiKey
        self.jellyfinUploadEnabled = jellyfinUploadEnabled
        self.jellyfinMovieLibraryId = jellyfinMovieLibraryId
        self.jellyfinTvLibraryId = jellyfinTvLibraryId
        self.jellyfinMovieServerPath = jellyfinMovieServerPath
        self.jellyfinTvServerPath = jellyfinTvServerPath
    }

    /// Load configuration by searching Keychain, UserDefaults (app settings), config files, and environment variables
    public static func load(from customPath: URL? = nil) -> PipelineConfig {
        var config = PipelineConfig()
        let home = FileManager.default.homeDirectoryForCurrentUser

        // 1. Search candidate configuration files
        let candidatePaths: [URL] = [
            customPath,
            URL(fileURLWithPath: "rip_pipeline.conf"),
            home.appendingPathComponent("scripts/rip_pipeline.conf"),
            home.appendingPathComponent(".config/rip_pipeline/rip_pipeline.conf"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("rip_pipeline.conf")
        ].compactMap { $0 }

        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                if let parsed = parse(from: path) {
                    config = parsed
                    break
                }
            }
        }

        // 2. Override sensitive keys with Secure Keychain
        if let key = KeychainHelper.shared.get(forKey: "omdbKey"), !key.isEmpty {
            config.omdbKey = key
        }
        if let osKey = KeychainHelper.shared.get(forKey: "openSubtitlesKey"), !osKey.isEmpty {
            config.openSubtitlesKey = osKey
        }
        if let osPass = KeychainHelper.shared.get(forKey: "openSubtitlesPassword"), !osPass.isEmpty {
            config.openSubtitlesPassword = osPass
        }
        if let jfKey = KeychainHelper.shared.get(forKey: "jellyfinApiKey"), !jfKey.isEmpty {
            config.jellyfinApiKey = jfKey
        }

        // 3. Override non-sensitive preferences with UserDefaults (Mac App Settings UI)
        let defaults = UserDefaults.standard
        if let osUser = defaults.string(forKey: "openSubtitlesUsername"), !osUser.isEmpty {
            config.openSubtitlesUsername = osUser
        }
        if let watch = defaults.string(forKey: "watchDir"), !watch.isEmpty {
            config.watchDir = URL(fileURLWithPath: (watch as NSString).expandingTildeInPath)
        }
        if let lib = defaults.string(forKey: "libraryDir"), !lib.isEmpty {
            config.libraryDir = URL(fileURLWithPath: (lib as NSString).expandingTildeInPath)
        }
        if let tvLib = defaults.string(forKey: "tvLibraryDir"), !tvLib.isEmpty {
            config.tvLibraryDir = URL(fileURLWithPath: (tvLib as NSString).expandingTildeInPath)
        }
        if let subLang = defaults.string(forKey: "subtitleLanguage"), !subLang.isEmpty {
            config.subtitleLanguage = subLang
        }
        if let subFmt = defaults.string(forKey: "subtitleFormat"), !subFmt.isEmpty {
            config.subtitleFormat = subFmt
        }

        // Subtitle Retention & Codecs
        if let retMode = defaults.string(forKey: "subtitleRetentionMode"), !retMode.isEmpty {
            config.subtitleRetentionMode = retMode
        }
        if let customLang = defaults.string(forKey: "customSubtitleLanguages"), !customLang.isEmpty {
            config.customSubtitleLanguages = customLang
        }
        if defaults.object(forKey: "keepSubRip") != nil { config.keepSubRip = defaults.bool(forKey: "keepSubRip") }
        if defaults.object(forKey: "keepAssSsa") != nil { config.keepAssSsa = defaults.bool(forKey: "keepAssSsa") }
        if defaults.object(forKey: "keepBitmapSubs") != nil { config.keepBitmapSubs = defaults.bool(forKey: "keepBitmapSubs") }
        if defaults.object(forKey: "preferEmbeddedSubs") != nil { config.preferEmbeddedSubs = defaults.bool(forKey: "preferEmbeddedSubs") }
        if defaults.object(forKey: "normalizeEmbeddedAllCaps") != nil { config.normalizeEmbeddedAllCaps = defaults.bool(forKey: "normalizeEmbeddedAllCaps") }
        if defaults.object(forKey: "clearDefaultSubtitleFlags") != nil { config.clearDefaultSubtitleFlags = defaults.bool(forKey: "clearDefaultSubtitleFlags") }

        // Subtitle Restrictions & Checks
        if defaults.object(forKey: "excludeHDTV") != nil { config.excludeHDTV = defaults.bool(forKey: "excludeHDTV") }
        if defaults.object(forKey: "excludeHearingImpaired") != nil { config.excludeHearingImpaired = defaults.bool(forKey: "excludeHearingImpaired") }
        if defaults.object(forKey: "excludeCommentary") != nil { config.excludeCommentary = defaults.bool(forKey: "excludeCommentary") }
        if defaults.object(forKey: "preferExtendedCuts") != nil { config.preferExtendedCuts = defaults.bool(forKey: "preferExtendedCuts") }
        if defaults.object(forKey: "matchVideoFPS") != nil { config.matchVideoFPS = defaults.bool(forKey: "matchVideoFPS") }
        if defaults.object(forKey: "enforceDurationCheck") != nil { config.enforceDurationCheck = defaults.bool(forKey: "enforceDurationCheck") }
        if defaults.object(forKey: "enforceContentCheck") != nil { config.enforceContentCheck = defaults.bool(forKey: "enforceContentCheck") }
        if defaults.object(forKey: "enforceStructuralAlignmentCheck") != nil { config.enforceStructuralAlignmentCheck = defaults.bool(forKey: "enforceStructuralAlignmentCheck") }

        // Subtitle Processing & Sync
        if defaults.object(forKey: "stripSubtitleAds") != nil { config.stripSubtitleAds = defaults.bool(forKey: "stripSubtitleAds") }
        if defaults.object(forKey: "stripSubtitleFormatting") != nil { config.stripSubtitleFormatting = defaults.bool(forKey: "stripSubtitleFormatting") }
        if defaults.object(forKey: "normalizeSubtitleCase") != nil { config.normalizeSubtitleCase = defaults.bool(forKey: "normalizeSubtitleCase") }
        if defaults.object(forKey: "syncSubtitlesAudio") != nil { config.syncSubtitlesAudio = defaults.bool(forKey: "syncSubtitlesAudio") }

        // Interactive Prompt Toggles
        if defaults.object(forKey: "promptForSubtitleFallback") != nil { config.promptForSubtitleFallback = defaults.bool(forKey: "promptForSubtitleFallback") }
        if defaults.object(forKey: "promptForAmbiguousTitles") != nil { config.promptForAmbiguousTitles = defaults.bool(forKey: "promptForAmbiguousTitles") }

        // Jellyfin
        if let jfURL = defaults.string(forKey: "jellyfinServerURL"), !jfURL.isEmpty {
            config.jellyfinServerURL = jfURL
        }
        if defaults.object(forKey: "jellyfinUploadEnabled") != nil {
            config.jellyfinUploadEnabled = defaults.bool(forKey: "jellyfinUploadEnabled")
        }
        if let jfMovieLib = defaults.string(forKey: "jellyfinMovieLibraryId") {
            config.jellyfinMovieLibraryId = jfMovieLib
        }
        if let jfTvLib = defaults.string(forKey: "jellyfinTvLibraryId") {
            config.jellyfinTvLibraryId = jfTvLib
        }
        if let jfMoviePath = defaults.string(forKey: "jellyfinMovieServerPath") {
            config.jellyfinMovieServerPath = jfMoviePath
        }
        if let jfTvPath = defaults.string(forKey: "jellyfinTvServerPath") {
            config.jellyfinTvServerPath = jfTvPath
        }

        // 4. Override with environment variables
        let env = ProcessInfo.processInfo.environment
        if let omdb = env["OMDB_API_KEY"], !omdb.isEmpty {
            config.omdbKey = omdb
        }
        if let osKey = env["OPENSUBTITLES_API_KEY"], !osKey.isEmpty {
            config.openSubtitlesKey = osKey
        }
        if let jfURL = env["JELLYFIN_SERVER_URL"], !jfURL.isEmpty {
            config.jellyfinServerURL = jfURL
        }
        if let jfKey = env["JELLYFIN_API_KEY"], !jfKey.isEmpty {
            config.jellyfinApiKey = jfKey
        }

        return config
    }

    /// Save current settings to Secure Keychain (API keys & passwords) and UserDefaults (general preferences)
    public func saveToUserDefaults() {
        // Securely store API keys and sensitive tokens in Keychain
        KeychainHelper.shared.set(omdbKey, forKey: "omdbKey")
        KeychainHelper.shared.set(openSubtitlesKey, forKey: "openSubtitlesKey")
        KeychainHelper.shared.set(openSubtitlesPassword, forKey: "openSubtitlesPassword")
        KeychainHelper.shared.set(jellyfinApiKey, forKey: "jellyfinApiKey")

        // Store non-sensitive settings in UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(openSubtitlesUsername, forKey: "openSubtitlesUsername")
        defaults.set(watchDir.path, forKey: "watchDir")
        defaults.set(libraryDir.path, forKey: "libraryDir")
        defaults.set(tvLibraryDir.path, forKey: "tvLibraryDir")
        defaults.set(subtitleLanguage, forKey: "subtitleLanguage")
        defaults.set(subtitleFormat, forKey: "subtitleFormat")

        defaults.set(subtitleRetentionMode, forKey: "subtitleRetentionMode")
        defaults.set(customSubtitleLanguages, forKey: "customSubtitleLanguages")
        defaults.set(keepSubRip, forKey: "keepSubRip")
        defaults.set(keepAssSsa, forKey: "keepAssSsa")
        defaults.set(keepBitmapSubs, forKey: "keepBitmapSubs")
        defaults.set(preferEmbeddedSubs, forKey: "preferEmbeddedSubs")
        defaults.set(normalizeEmbeddedAllCaps, forKey: "normalizeEmbeddedAllCaps")
        defaults.set(clearDefaultSubtitleFlags, forKey: "clearDefaultSubtitleFlags")

        defaults.set(excludeHDTV, forKey: "excludeHDTV")
        defaults.set(excludeHearingImpaired, forKey: "excludeHearingImpaired")
        defaults.set(excludeCommentary, forKey: "excludeCommentary")
        defaults.set(preferExtendedCuts, forKey: "preferExtendedCuts")
        defaults.set(matchVideoFPS, forKey: "matchVideoFPS")
        defaults.set(enforceDurationCheck, forKey: "enforceDurationCheck")
        defaults.set(enforceContentCheck, forKey: "enforceContentCheck")
        defaults.set(enforceStructuralAlignmentCheck, forKey: "enforceStructuralAlignmentCheck")

        defaults.set(stripSubtitleAds, forKey: "stripSubtitleAds")
        defaults.set(stripSubtitleFormatting, forKey: "stripSubtitleFormatting")
        defaults.set(normalizeSubtitleCase, forKey: "normalizeSubtitleCase")
        defaults.set(syncSubtitlesAudio, forKey: "syncSubtitlesAudio")

        defaults.set(promptForSubtitleFallback, forKey: "promptForSubtitleFallback")
        defaults.set(promptForAmbiguousTitles, forKey: "promptForAmbiguousTitles")

        defaults.set(jellyfinServerURL, forKey: "jellyfinServerURL")
        defaults.set(jellyfinUploadEnabled, forKey: "jellyfinUploadEnabled")
        defaults.set(jellyfinMovieLibraryId, forKey: "jellyfinMovieLibraryId")
        defaults.set(jellyfinTvLibraryId, forKey: "jellyfinTvLibraryId")
        defaults.set(jellyfinMovieServerPath, forKey: "jellyfinMovieServerPath")
        defaults.set(jellyfinTvServerPath, forKey: "jellyfinTvServerPath")
    }

    /// Alias for saveToUserDefaults() reflecting that sensitive keys are kept in Keychain
    public func save() {
        saveToUserDefaults()
    }

    private static func parse(from url: URL) -> PipelineConfig? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var config = PipelineConfig()
        var currentSection = ""

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.dropFirst().dropLast().isEmpty == false && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).lowercased()
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let val = parts[1]
            let boolVal = (val.lowercased() == "true" || val == "1" || val.lowercased() == "yes")

            switch currentSection {
            case "paths":
                let expanded = (val as NSString).expandingTildeInPath
                let pathURL = URL(fileURLWithPath: expanded)
                if key == "watch_dir" { config.watchDir = pathURL }
                else if key == "library_dir" { config.libraryDir = pathURL }
                else if key == "tv_library_dir" { config.tvLibraryDir = pathURL }
            case "api":
                if key == "omdb_key" { config.omdbKey = val }
                else if key == "opensubtitles_key" { config.openSubtitlesKey = val }
                else if key == "opensubtitles_user_agent" { config.openSubtitlesUserAgent = val }
                else if key == "opensubtitles_username" { config.openSubtitlesUsername = val }
                else if key == "opensubtitles_password" { config.openSubtitlesPassword = val }
            case "subtitles":
                if key == "language" { config.subtitleLanguage = val }
                else if key == "format" { config.subtitleFormat = val }
                else if key == "retention_mode" { config.subtitleRetentionMode = val }
                else if key == "custom_languages" { config.customSubtitleLanguages = val }
                else if key == "keep_subrip" { config.keepSubRip = boolVal }
                else if key == "keep_ass_ssa" { config.keepAssSsa = boolVal }
                else if key == "keep_bitmap" { config.keepBitmapSubs = boolVal }
                else if key == "prefer_embedded" { config.preferEmbeddedSubs = boolVal }
                else if key == "normalize_embedded_caps" { config.normalizeEmbeddedAllCaps = boolVal }
                else if key == "clear_defaults" { config.clearDefaultSubtitleFlags = boolVal }
                else if key == "exclude_hdtv" { config.excludeHDTV = boolVal }
                else if key == "exclude_hearing_impaired" { config.excludeHearingImpaired = boolVal }
                else if key == "exclude_commentary" { config.excludeCommentary = boolVal }
                else if key == "prefer_extended" { config.preferExtendedCuts = boolVal }
                else if key == "match_fps" { config.matchVideoFPS = boolVal }
                else if key == "enforce_duration" { config.enforceDurationCheck = boolVal }
                else if key == "enforce_content" { config.enforceContentCheck = boolVal }
                else if key == "enforce_structure" { config.enforceStructuralAlignmentCheck = boolVal }
                else if key == "strip_ads" { config.stripSubtitleAds = boolVal }
                else if key == "strip_formatting" { config.stripSubtitleFormatting = boolVal }
                else if key == "normalize_case" { config.normalizeSubtitleCase = boolVal }
                else if key == "sync_audio" { config.syncSubtitlesAudio = boolVal }
                else if key == "prompt_fallback" { config.promptForSubtitleFallback = boolVal }
                else if key == "prompt_ambiguous_titles" { config.promptForAmbiguousTitles = boolVal }
            case "jellyfin":
                if key == "server_url" { config.jellyfinServerURL = val }
                else if key == "api_key" { config.jellyfinApiKey = val }
                else if key == "upload_enabled" { config.jellyfinUploadEnabled = boolVal }
                else if key == "movie_library_id" { config.jellyfinMovieLibraryId = val }
                else if key == "tv_library_id" { config.jellyfinTvLibraryId = val }
                else if key == "movie_server_path" { config.jellyfinMovieServerPath = val }
                else if key == "tv_server_path" { config.jellyfinTvServerPath = val }
            default:
                break
            }
        }

        return config
    }
}
