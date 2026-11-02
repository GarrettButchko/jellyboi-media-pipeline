import Foundation

public enum SourceType: String, Sendable {
    case dvd
    case bluray

    public var displayTitle: String {
        switch self {
        case .dvd: return "DVD"
        case .bluray: return "BLURAY"
        }
    }
}

public struct ParsedTitle: Sendable {
    public let title: String
    public let yearHint: String?
    public let durationMinutes: Double?
    public let isFromMetadata: Bool

    public init(title: String, yearHint: String?, durationMinutes: Double?, isFromMetadata: Bool) {
        self.title = title
        self.yearHint = yearHint
        self.durationMinutes = durationMinutes
        self.isFromMetadata = isFromMetadata
    }
}

public struct CropEdges: Sendable, Equatable {
    public let top: Int
    public let bottom: Int
    public let left: Int
    public let right: Int

    public var isMeaningful: Bool {
        top > 0 || bottom > 0 || left > 0 || right > 0
    }

    public init(top: Int, bottom: Int, left: Int, right: Int, minPx: Int = 8) {
        self.top = top >= minPx ? top : 0
        self.bottom = bottom >= minPx ? bottom : 0
        self.left = left >= minPx ? left : 0
        self.right = right >= minPx ? right : 0
    }
}

public struct VideoDimensions: Sendable {
    public let width: Int
    public let height: Int
    public let par: Double

    public init(width: Int, height: Int, par: Double) {
        self.width = width
        self.height = height
        self.par = par
    }
}

public struct MKVTrack: Sendable {
    public let id: Int
    public let type: String
    public let codec: String
    public let codecId: String
    public let language: String
    public let isDefault: Bool
    public let isForced: Bool

    public var isAudio: Bool { type == "audio" }
    public var isSubtitle: Bool { type == "subtitles" }
    public var isVideo: Bool { type == "video" }

    public var isEnglishAudio: Bool {
        isAudio && ["eng", "en", "und"].contains(language.lowercased())
    }

    public var isEnglishSubtitle: Bool {
        isSubtitle && ["eng", "en", "und"].contains(language.lowercased())
    }

    public var isSubRip: Bool {
        let cid = codecId.uppercased()
        let c = codec.lowercased()
        return cid == "S_TEXT/UTF8" || cid == "S_TEXT/UTF16" || cid == "S_TEXT/ASCII" || c.contains("subrip")
    }

    public init(id: Int, type: String, codec: String, codecId: String, language: String, isDefault: Bool, isForced: Bool) {
        self.id = id
        self.type = type
        self.codec = codec
        self.codecId = codecId
        self.language = language
        self.isDefault = isDefault
        self.isForced = isForced
    }
}

public struct MovieMatch: Sendable {
    public let title: String
    public let year: String
    public let imdbId: String
    public let votes: Int?
    public let runtimeMinutes: Int?

    public init(title: String, year: String, imdbId: String, votes: Int? = nil, runtimeMinutes: Int? = nil) {
        self.title = title
        self.year = year
        self.imdbId = imdbId
        self.votes = votes
        self.runtimeMinutes = runtimeMinutes
    }
}

public struct TVEpisodeMatch: Sendable {
    public let seriesTitle: String
    public let seriesYear: String
    public let seriesImdbId: String
    public let season: Int
    public let episode: Int
    public let episodeTitle: String
    public let episodeImdbId: String

    public init(
        seriesTitle: String,
        seriesYear: String,
        seriesImdbId: String,
        season: Int,
        episode: Int,
        episodeTitle: String,
        episodeImdbId: String
    ) {
        self.seriesTitle = seriesTitle
        self.seriesYear = seriesYear
        self.seriesImdbId = seriesImdbId
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
        self.episodeImdbId = episodeImdbId
    }
}

public struct SubtitleCandidate: Sendable {
    public let fileId: String
    public let release: String
    public let score: Int
    public let downloadCount: Int
    public let hearingImpaired: Bool
    public let fps: Double?

    public init(
        fileId: String,
        release: String,
        score: Int,
        downloadCount: Int,
        hearingImpaired: Bool,
        fps: Double?
    ) {
        self.fileId = fileId
        self.release = release
        self.score = score
        self.downloadCount = downloadCount
        self.hearingImpaired = hearingImpaired
        self.fps = fps
    }
}

// MARK: - Jellyfin Plugin Integration Models

public struct JellyfinServerStatus: Sendable, Codable, Equatable {
    public let plugin: String?
    public let installed: Bool
    public let version: String?
    public let directUploadsEnabled: Bool?
    public let serverName: String?

    public init(
        plugin: String? = "FileToRemux",
        installed: Bool = true,
        version: String? = "1.0.0",
        directUploadsEnabled: Bool? = true,
        serverName: String? = nil
    ) {
        self.plugin = plugin
        self.installed = installed
        self.version = version
        self.directUploadsEnabled = directUploadsEnabled
        self.serverName = serverName
    }

    enum CodingKeys: String, CodingKey {
        case plugin, Plugin
        case installed, Installed
        case version, Version
        case directUploadsEnabled, DirectUploadsEnabled
        case serverName, ServerName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.plugin = (try? container.decodeIfPresent(String.self, forKey: .plugin))
            ?? (try? container.decodeIfPresent(String.self, forKey: .Plugin))
        self.installed = (try? container.decodeIfPresent(Bool.self, forKey: .installed))
            ?? (try? container.decodeIfPresent(Bool.self, forKey: .Installed))
            ?? true
        self.version = (try? container.decodeIfPresent(String.self, forKey: .version))
            ?? (try? container.decodeIfPresent(String.self, forKey: .Version))
        self.directUploadsEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .directUploadsEnabled))
            ?? (try? container.decodeIfPresent(Bool.self, forKey: .DirectUploadsEnabled))
        self.serverName = (try? container.decodeIfPresent(String.self, forKey: .serverName))
            ?? (try? container.decodeIfPresent(String.self, forKey: .ServerName))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(plugin, forKey: .plugin)
        try container.encode(installed, forKey: .installed)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(directUploadsEnabled, forKey: .directUploadsEnabled)
        try container.encodeIfPresent(serverName, forKey: .serverName)
    }
}

public struct JellyfinLibrary: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let collectionType: String
    public let path: String?
    public let locations: [String]

    public init(id: String, name: String, collectionType: String, path: String? = nil, locations: [String] = []) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
        self.path = path ?? locations.first
        self.locations = !locations.isEmpty ? locations : (path != nil ? [path!] : [])
    }

    public var effectivePath: String? {
        path ?? locations.first
    }

    enum CodingKeys: String, CodingKey {
        case id, Id, ItemId
        case name, Name
        case collectionType, CollectionType
        case path, Path
        case locations, Locations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(String.self, forKey: .id))
            ?? (try? container.decodeIfPresent(String.self, forKey: .Id))
            ?? (try? container.decodeIfPresent(String.self, forKey: .ItemId))
            ?? UUID().uuidString
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name))
            ?? (try? container.decodeIfPresent(String.self, forKey: .Name))
            ?? "Unknown Library"
        self.collectionType = (try? container.decodeIfPresent(String.self, forKey: .collectionType))
            ?? (try? container.decodeIfPresent(String.self, forKey: .CollectionType))
            ?? "unknown"
        let locs = (try? container.decodeIfPresent([String].self, forKey: .locations))
            ?? (try? container.decodeIfPresent([String].self, forKey: .Locations))
            ?? []
        let singlePath = (try? container.decodeIfPresent(String.self, forKey: .path))
            ?? (try? container.decodeIfPresent(String.self, forKey: .Path))
        self.path = singlePath ?? locs.first
        self.locations = !locs.isEmpty ? locs : (singlePath != nil ? [singlePath!] : [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(collectionType, forKey: .collectionType)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encode(locations, forKey: .locations)
    }
}

public enum JellyfinDetectionState: Sendable, Equatable {
    case idle
    case checking
    case detected(version: String, serverName: String?)
    case pluginMissing(serverName: String?)
    case unauthorized
    case unreachable(message: String)
}

public enum JellyfinMediaType: String, Sendable, Codable, CaseIterable {
    case movie = "Movie"
    case tvEpisode = "TV Episode"
}

public enum JellyfinUploadStatus: String, Sendable, Codable, CaseIterable {
    case queued = "Queued"
    case uploading = "Uploading"
    case completed = "Uploaded"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

public struct JellyfinUploadItem: Identifiable, Sendable {
    public let id: UUID
    public var fileURL: URL
    public var fileName: String
    public var fileSizeBytes: Int64
    public var mediaType: JellyfinMediaType
    public var title: String
    public var year: String?
    public var imdbId: String?
    public var season: Int?
    public var episode: Int?
    public var episodeTitle: String?
    public var targetLibraryId: String?
    public var targetServerPath: String?
    public var status: JellyfinUploadStatus
    public var progressFraction: Double
    public var statusDetail: String
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        fileName: String? = nil,
        fileSizeBytes: Int64? = nil,
        mediaType: JellyfinMediaType = .movie,
        title: String,
        year: String? = nil,
        imdbId: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil,
        targetLibraryId: String? = nil,
        targetServerPath: String? = nil,
        status: JellyfinUploadStatus = .queued,
        progressFraction: Double = 0.0,
        statusDetail: String = "Queued",
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileName = fileName ?? fileURL.lastPathComponent
        let size = fileSizeBytes ?? ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0)
        self.fileSizeBytes = size
        self.mediaType = mediaType
        self.title = title
        self.year = year
        self.imdbId = imdbId
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
        self.targetLibraryId = targetLibraryId
        self.targetServerPath = targetServerPath
        self.status = status
        self.progressFraction = progressFraction
        self.statusDetail = statusDetail
        self.errorMessage = errorMessage
    }

    public var fileSizeString: String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useGB, .useMB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: fileSizeBytes)
    }
}
