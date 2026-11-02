import Foundation

/// Configuration loaded from rip_pipeline.conf, UserDefaults, or environment variables.
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
        self.jellyfinServerURL = jellyfinServerURL
        self.jellyfinApiKey = jellyfinApiKey
        self.jellyfinUploadEnabled = jellyfinUploadEnabled
        self.jellyfinMovieLibraryId = jellyfinMovieLibraryId
        self.jellyfinTvLibraryId = jellyfinTvLibraryId
        self.jellyfinMovieServerPath = jellyfinMovieServerPath
        self.jellyfinTvServerPath = jellyfinTvServerPath
    }

    /// Load configuration by searching UserDefaults (app settings), config files, and environment variables
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

        // 2. Override with UserDefaults (Mac App Settings UI)
        let defaults = UserDefaults.standard
        if let key = defaults.string(forKey: "omdbKey"), !key.isEmpty {
            config.omdbKey = key
        }
        if let osKey = defaults.string(forKey: "openSubtitlesKey"), !osKey.isEmpty {
            config.openSubtitlesKey = osKey
        }
        if let osUser = defaults.string(forKey: "openSubtitlesUsername"), !osUser.isEmpty {
            config.openSubtitlesUsername = osUser
        }
        if let osPass = defaults.string(forKey: "openSubtitlesPassword"), !osPass.isEmpty {
            config.openSubtitlesPassword = osPass
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
        if let jfURL = defaults.string(forKey: "jellyfinServerURL"), !jfURL.isEmpty {
            config.jellyfinServerURL = jfURL
        }
        if let jfKey = defaults.string(forKey: "jellyfinApiKey"), !jfKey.isEmpty {
            config.jellyfinApiKey = jfKey
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

        // 3. Override with environment variables
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

    /// Save current settings to UserDefaults for Mac App persistence
    public func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(omdbKey, forKey: "omdbKey")
        defaults.set(openSubtitlesKey, forKey: "openSubtitlesKey")
        defaults.set(openSubtitlesUsername, forKey: "openSubtitlesUsername")
        defaults.set(openSubtitlesPassword, forKey: "openSubtitlesPassword")
        defaults.set(watchDir.path, forKey: "watchDir")
        defaults.set(libraryDir.path, forKey: "libraryDir")
        defaults.set(tvLibraryDir.path, forKey: "tvLibraryDir")
        defaults.set(jellyfinServerURL, forKey: "jellyfinServerURL")
        defaults.set(jellyfinApiKey, forKey: "jellyfinApiKey")
        defaults.set(jellyfinUploadEnabled, forKey: "jellyfinUploadEnabled")
        defaults.set(jellyfinMovieLibraryId, forKey: "jellyfinMovieLibraryId")
        defaults.set(jellyfinTvLibraryId, forKey: "jellyfinTvLibraryId")
        defaults.set(jellyfinMovieServerPath, forKey: "jellyfinMovieServerPath")
        defaults.set(jellyfinTvServerPath, forKey: "jellyfinTvServerPath")
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

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).lowercased()
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let val = parts[1]

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
            case "jellyfin":
                if key == "server_url" { config.jellyfinServerURL = val }
                else if key == "api_key" { config.jellyfinApiKey = val }
                else if key == "upload_enabled" { config.jellyfinUploadEnabled = (val.lowercased() == "true" || val == "1") }
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
