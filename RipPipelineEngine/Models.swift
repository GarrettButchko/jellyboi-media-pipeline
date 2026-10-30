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
