import Foundation

/// Errors that can occur when communicating with a Jellyfin server or the FileToRemux plugin.
public enum JellyfinError: LocalizedError, Sendable {
    case invalidServerURL
    case serverUnreachable(String)
    case unauthorized
    case pluginNotInstalled(serverName: String?)
    case libraryNotFound
    case uploadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid Jellyfin server URL. Please enter a valid address (e.g. http://192.168.1.100:8096)."
        case .serverUnreachable(let message):
            return "Cannot reach Jellyfin server: \(message)"
        case .unauthorized:
            return "Unauthorized. The provided Jellyfin API Key or token is invalid."
        case .pluginNotInstalled(let name):
            let server = name != nil ? " on '\(name!)'" : ""
            return "Jellyfin server is online, but the FileToRemux plugin is not installed\(server)."
        case .libraryNotFound:
            return "Target Jellyfin library could not be found."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        }
    }
}

/// Client providing status detection, library querying, and direct streaming uploads to a Jellyfin server running the FileToRemux plugin.
public struct JellyfinClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Normalizes a user-entered URL string into a valid HTTP/HTTPS URL
    public static func normalizeURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            ? trimmed
            : "http://" + trimmed

        let strippedTrailing = withScheme.hasSuffix("/")
            ? String(withScheme.dropLast())
            : withScheme

        return URL(string: strippedTrailing)
    }

    /// Tests the connection to the Jellyfin server and checks whether the FileToRemux plugin is installed.
    public func checkStatus(serverURL: String, apiKey: String? = nil) async -> JellyfinDetectionState {
        guard let baseURL = Self.normalizeURL(serverURL) else {
            return .unreachable(message: "Invalid server URL")
        }

        // 1. First probe the FileToRemux plugin status endpoint
        let pluginURL = baseURL.appendingPathComponent("FileToRemux/Status")
        var request = URLRequest(url: pluginURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0
        if let key = apiKey?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-Emby-Token")
            request.setValue("MediaBrowser Token=\"\(key)\"", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(message: "Unexpected response from server")
            }

            if http.statusCode == 200 {
                if let status = try? JSONDecoder().decode(JellyfinServerStatus.self, from: data) {
                    return .detected(
                        version: status.version ?? "1.0.0",
                        serverName: status.serverName
                    )
                }
                return .detected(version: "1.0.0", serverName: nil)
            } else if http.statusCode == 401 || http.statusCode == 403 {
                return .unauthorized
            } else if http.statusCode == 404 {
                // Plugin endpoint returned 404. Let's verify whether the server itself is Jellyfin
                return await probeJellyfinPublicInfo(baseURL: baseURL)
            } else {
                return .unreachable(message: "Server returned HTTP \(http.statusCode)")
            }
        } catch {
            // Network failure or timeout on plugin endpoint, test if Jellyfin root responds
            return await probeJellyfinPublicInfo(baseURL: baseURL, fallbackError: error.localizedDescription)
        }
    }

    /// Probes Jellyfin's standard /System/Info/Public endpoint to confirm if the server is alive
    private func probeJellyfinPublicInfo(baseURL: URL, fallbackError: String? = nil) async -> JellyfinDetectionState {
        let publicInfoURL = baseURL.appendingPathComponent("System/Info/Public")
        var request = URLRequest(url: publicInfoURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let serverName = json["ServerName"] as? String {
                    return .pluginMissing(serverName: serverName)
                }
                return .pluginMissing(serverName: nil)
            }
        } catch {
            // Both failed
        }

        return .unreachable(message: fallbackError ?? "Server is unreachable or not a Jellyfin server")
    }

    /// Fetches the available media libraries from the Jellyfin server
    public func fetchLibraries(serverURL: String, apiKey: String) async throws -> [JellyfinLibrary] {
        guard let baseURL = Self.normalizeURL(serverURL) else {
            throw JellyfinError.invalidServerURL
        }

        // Try the FileToRemux Libraries endpoint first
        let endpoint = baseURL.appendingPathComponent("FileToRemux/Libraries")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 12.0
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        request.setValue(key, forHTTPHeaderField: "X-Emby-Token")
        request.setValue("MediaBrowser Token=\"\(key)\"", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JellyfinError.serverUnreachable("Invalid server response")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw JellyfinError.unauthorized
        }

        if http.statusCode == 200 {
            if let list = try? JSONDecoder().decode([JellyfinLibrary].self, from: data) {
                return list
            }
        }

        // Fallback: standard Jellyfin /Library/VirtualFolders
        return try await fetchLibrariesFallback(baseURL: baseURL, apiKey: key)
    }

    private func fetchLibrariesFallback(baseURL: URL, apiKey: String) async throws -> [JellyfinLibrary] {
        let endpoint = baseURL.appendingPathComponent("Library/VirtualFolders")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 12.0
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        request.setValue(key, forHTTPHeaderField: "X-Emby-Token")
        request.setValue("MediaBrowser Token=\"\(key)\"", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { dict in
            guard let id = dict["ItemId"] as? String ?? dict["Id"] as? String,
                  let name = dict["Name"] as? String else {
                return nil
            }
            let collection = dict["CollectionType"] as? String ?? "unknown"
            let paths = dict["Locations"] as? [String] ?? []
            return JellyfinLibrary(id: id, name: name, collectionType: collection, path: paths.first, locations: paths)
        }
    }

    /// Streams an MKV movie directly to the Jellyfin server via the FileToRemux plugin
    public func uploadMovie(
        fileURL: URL,
        title: String,
        year: String,
        imdbId: String,
        libraryId: String?,
        serverPath: String? = nil,
        serverURL: String,
        apiKey: String,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let baseURL = Self.normalizeURL(serverURL) else {
            throw JellyfinError.invalidServerURL
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw JellyfinError.uploadFailed("Source file does not exist: \(fileURL.path)")
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("FileToRemux/Upload/Movie"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "year", value: year),
            URLQueryItem(name: "imdbId", value: imdbId)
        ]
        if let libId = libraryId, !libId.isEmpty {
            queryItems.append(URLQueryItem(name: "libraryId", value: libId))
        }
        if let sPath = serverPath, !sPath.isEmpty {
            queryItems.append(URLQueryItem(name: "serverPath", value: sPath))
        }
        components?.queryItems = queryItems

        guard let uploadURL = components?.url else {
            throw JellyfinError.invalidServerURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        request.setValue(key, forHTTPHeaderField: "X-Emby-Token")
        request.setValue("MediaBrowser Token=\"\(key)\"", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 7200.0 // 2 hours for large remuxes

        try await performUpload(request: request, fromFile: fileURL, progressHandler: progressHandler)
    }

    /// Streams an MKV TV episode directly to the Jellyfin server via the FileToRemux plugin
    public func uploadEpisode(
        fileURL: URL,
        seriesTitle: String,
        seriesYear: String,
        seriesImdbId: String,
        season: Int,
        episode: Int,
        episodeTitle: String,
        libraryId: String?,
        serverPath: String? = nil,
        serverURL: String,
        apiKey: String,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let baseURL = Self.normalizeURL(serverURL) else {
            throw JellyfinError.invalidServerURL
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw JellyfinError.uploadFailed("Source file does not exist: \(fileURL.path)")
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("FileToRemux/Upload/Episode"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "seriesTitle", value: seriesTitle),
            URLQueryItem(name: "seriesYear", value: seriesYear),
            URLQueryItem(name: "seriesImdbId", value: seriesImdbId),
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "episode", value: String(episode)),
            URLQueryItem(name: "episodeTitle", value: episodeTitle)
        ]
        if let libId = libraryId, !libId.isEmpty {
            queryItems.append(URLQueryItem(name: "libraryId", value: libId))
        }
        if let sPath = serverPath, !sPath.isEmpty {
            queryItems.append(URLQueryItem(name: "serverPath", value: sPath))
        }
        components?.queryItems = queryItems

        guard let uploadURL = components?.url else {
            throw JellyfinError.invalidServerURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        request.setValue(key, forHTTPHeaderField: "X-Emby-Token")
        request.setValue("MediaBrowser Token=\"\(key)\"", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 7200.0

        try await performUpload(request: request, fromFile: fileURL, progressHandler: progressHandler)
    }

    /// Uploads the request body, retrying a bounded number of times for transient connection failures.
    /// URLSession cannot resume file-backed uploads, so each retry restarts the transfer from the beginning.
    private func performUpload(
        request: URLRequest,
        fromFile fileURL: URL,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let maxAttempts = 3
        let retryDelays: [Duration] = [.seconds(3), .seconds(10)]

        var attempt = 1
        while true {
            do {
                let delegate = UploadTaskDelegate()
                delegate.progressHandler = progressHandler
                let (data, response) = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)

                guard let http = response as? HTTPURLResponse else {
                    throw JellyfinError.uploadFailed("Invalid server response")
                }

                // URLSession treats any completed HTTP exchange as success. Without this
                // check a 409/500 returned by the plugin was reported as a finished upload.
                if !(200...299).contains(http.statusCode) {
                    if http.statusCode >= 500, attempt < maxAttempts {
                        let delay = retryDelays[min(attempt - 1, retryDelays.count - 1)]
                        try await Task.sleep(for: delay)
                        attempt += 1
                        continue
                    }

                    if http.statusCode == 401 || http.statusCode == 403 {
                        throw JellyfinError.unauthorized
                    }

                    throw JellyfinError.uploadFailed(
                        Self.serverErrorMessage(from: data, statusCode: http.statusCode)
                    )
                }

                progressHandler?(1.0)
                return
            } catch {
                guard attempt < maxAttempts, Self.isTransientUploadError(error) else {
                    throw error
                }
                let delay = retryDelays[min(attempt - 1, retryDelays.count - 1)]
                try await Task.sleep(for: delay)
                attempt += 1
            }
        }
    }

    /// Extracts a human-readable error from the plugin's JSON error body, falling back to
    /// the HTTP status when the server does not send one.
    private static func serverErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["Error"] as? String, !message.isEmpty {
                return message
            }
            if let title = json["title"] as? String, !title.isEmpty {
                return title
            }
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           text.count <= 500 {
            return text
        }

        switch statusCode {
        case 409:
            return "A file with this name already exists on the server."
        default:
            return "Server returned HTTP \(statusCode)"
        }
    }

    private static func isTransientUploadError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost,
             .resourceUnavailable, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    /// Forwards URLSessionUploadTask progress callbacks to the caller-supplied progress handler.
    private final class UploadTaskDelegate: NSObject, URLSessionTaskDelegate {
        var progressHandler: (@Sendable (Double) -> Void)?

        override init() {
            super.init()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            guard totalBytesExpectedToSend > 0 else { return }
            let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            progressHandler?(min(max(fraction, 0), 1))
        }
    }
}
