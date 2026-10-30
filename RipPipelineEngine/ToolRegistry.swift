import Foundation

public struct ToolStatus: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let path: String?
    public let isAvailable: Bool
    public let purpose: String

    public init(name: String, path: String?, purpose: String) {
        self.name = name
        self.path = path
        self.isAvailable = path != nil
        self.purpose = purpose
    }
}

/// Manages resolution and invocation of external media binaries across macOS environments.
public struct ToolRegistry: Sendable {
    public static let shared = ToolRegistry()

    public let ffprobe: String?
    public let ffmpeg: String?
    public let handBrakeCLI: String?
    public let mkvmerge: String?
    public let mkvpropedit: String?
    public let mkvextract: String?
    public let ffsubsync: String?
    public let alassCLI: String?

    public init(customOverrides: [String: String] = [:]) {
        self.ffprobe = customOverrides["ffprobe"] ?? Self.findBinary("ffprobe")
        self.ffmpeg = customOverrides["ffmpeg"] ?? Self.findBinary("ffmpeg")
        self.handBrakeCLI = customOverrides["HandBrakeCLI"] ?? Self.findBinary("HandBrakeCLI")
        self.mkvmerge = customOverrides["mkvmerge"] ?? Self.findBinary("mkvmerge")
        self.mkvpropedit = customOverrides["mkvpropedit"] ?? Self.findBinary("mkvpropedit")
        self.mkvextract = customOverrides["mkvextract"] ?? Self.findBinary("mkvextract")
        self.ffsubsync = customOverrides["ffsubsync"] ?? Self.findBinary("ffsubsync", extraDirs: Self.pythonDirs())
        self.alassCLI = customOverrides["alass-cli"] ?? customOverrides["alass"] ?? Self.findBinary("alass-cli") ?? Self.findBinary("alass")
    }

    private static func pythonDirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            (home as NSString).appendingPathComponent("Library/Python/3.9/bin"),
            (home as NSString).appendingPathComponent("Library/Python/3.10/bin"),
            (home as NSString).appendingPathComponent("Library/Python/3.11/bin"),
            (home as NSString).appendingPathComponent("Library/Python/3.12/bin"),
            (home as NSString).appendingPathComponent(".local/bin")
        ]
    }

    /// Search for binary in app bundle, system, Homebrew, and user tool directories
    public static func findBinary(_ name: String, extraDirs: [String] = []) -> String? {
        let fm = FileManager.default

        // 1. Check App Bundle helpers / resources
        if let bundleAux = Bundle.main.url(forAuxiliaryExecutable: name)?.path,
           fm.isExecutableFile(atPath: bundleAux) {
            return bundleAux
        }
        if let resourcePath = Bundle.main.resourcePath {
            let candidate = (resourcePath as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // 2. Search PATH environment variable
        var searchPaths: [String] = []
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            searchPaths.append(contentsOf: envPath.components(separatedBy: ":"))
        }

        // 3. Search standard macOS tool directories
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        searchPaths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            (home as NSString).appendingPathComponent(".local/bin"),
            (home as NSString).appendingPathComponent(".cargo/bin")
        ])
        searchPaths.append(contentsOf: extraDirs)

        for dir in searchPaths where !dir.isEmpty {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    public var allToolsStatus: [ToolStatus] {
        [
            ToolStatus(name: "ffprobe", path: ffprobe, purpose: "Media stream metadata inspection and duration extraction"),
            ToolStatus(name: "ffmpeg", path: ffmpeg, purpose: "Fast tail duration extraction and audio synchronization decoding"),
            ToolStatus(name: "HandBrakeCLI", path: handBrakeCLI, purpose: "Automatic black bar video crop detection"),
            ToolStatus(name: "mkvmerge", path: mkvmerge, purpose: "Matroska container remuxing and track filtering"),
            ToolStatus(name: "mkvpropedit", path: mkvpropedit, purpose: "Applying crop metadata and clearing default subtitle flags"),
            ToolStatus(name: "mkvextract", path: mkvextract, purpose: "Extracting embedded subtitle tracks for normalization"),
            ToolStatus(name: "ffsubsync", path: ffsubsync, purpose: "Audio-to-subtitle speech timing alignment"),
            ToolStatus(name: "alass-cli", path: alassCLI, purpose: "Video cut-aware subtitle synchronization for TV shows")
        ]
    }

    public func logDiagnostics() {
        for tool in allToolsStatus {
            if let path = tool.path {
                Logger.debug("Found \(tool.name): \(path)")
            } else {
                Logger.warning("Tool not found: \(tool.name) — \(tool.purpose)")
            }
        }
    }
}
