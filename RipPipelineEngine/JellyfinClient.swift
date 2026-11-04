import Foundation

/// Errors that can occur when communicating with a Jellyfin server or the Jellyboi File Upload plugin.
public enum JellyfinError: LocalizedError, Sendable {
    case invalidServerURL
    case serverUnreachable(String)
    case unauthorized
    case pluginNotInstalled(serverName: String?)
    case libraryNotFound
    case uploadFailed(String)
    case cancelled

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
            return "Jellyfin server is online, but the Jellyboi File Upload plugin is not installed\(server)."
        case .libraryNotFound:
            return "Target Jellyfin library could not be found."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .cancelled:
            return "Upload was cancelled."
        }
    }
}

/// Client providing status detection, library querying, and direct streaming uploads to a Jellyfin server running the Jellyboi File Upload plugin.
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

    /// Tests the connection to the Jellyfin server and checks whether the Jellyboi File Upload plugin is installed.
    public func checkStatus(serverURL: String, apiKey: String? = nil) async -> JellyfinDetectionState {
        guard let baseURL = Self.normalizeURL(serverURL) else {
            return .unreachable(message: "Invalid server URL")
        }

        // 1. First probe the Jellyboi File Upload plugin status endpoint
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

    /// Queries the Jellyfin server for existing upload progress/offset for a movie or TV episode
    public func fetchUploadProgress(
        serverURL: String,
        apiKey: String,
        title: String? = nil,
        year: String? = nil,
        imdbId: String? = nil,
        seriesTitle: String? = nil,
        seriesYear: String? = nil,
        seriesImdbId: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil,
        libraryId: String? = nil,
        serverPath: String? = nil
    ) async throws -> JellyfinUploadProgressResponse {
        guard let baseURL = Self.normalizeURL(serverURL) else {
            throw JellyfinError.invalidServerURL
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("FileToRemux/Upload/Progress"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []

        if let t = title, !t.isEmpty { queryItems.append(URLQueryItem(name: "title", value: t)) }
        if let y = year, !y.isEmpty { queryItems.append(URLQueryItem(name: "year", value: y)) }
        if let i = imdbId, !i.isEmpty { queryItems.append(URLQueryItem(name: "imdbId", value: i)) }

        if let st = seriesTitle, !st.isEmpty { queryItems.append(URLQueryItem(name: "seriesTitle", value: st)) }
        if let sy = seriesYear, !sy.isEmpty { queryItems.append(URLQueryItem(name: "seriesYear", value: sy)) }
        if let si = seriesImdbId, !si.isEmpty { queryItems.append(URLQueryItem(name: "seriesImdbId", value: si)) }
        if let s = season { queryItems.append(URLQueryItem(name: "season", value: String(s))) }
        if let ep = episode { queryItems.append(URLQueryItem(name: "episode", value: String(ep))) }
        if let et = episodeTitle, !et.isEmpty { queryItems.append(URLQueryItem(name: "episodeTitle", value: et)) }

        if let libId = libraryId, !libId.isEmpty { queryItems.append(URLQueryItem(name: "libraryId", value: libId)) }
        if let sPath = serverPath, !sPath.isEmpty { queryItems.append(URLQueryItem(name: "serverPath", value: sPath)) }

        components?.queryItems = queryItems

        guard let progressURL = components?.url else {
            throw JellyfinError.invalidServerURL
        }

        var request = URLRequest(url: progressURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        request.setValue(key, forHTTPHeaderField: "X-Emby-Token")
        request.setValue("MediaBrowser Token=\"\(key)\"", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JellyfinError.uploadFailed("Invalid server response when checking progress")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw JellyfinError.unauthorized
        }

        if !(200...299).contains(http.statusCode) {
            throw JellyfinError.uploadFailed(Self.serverErrorMessage(from: data, statusCode: http.statusCode))
        }

        let decoder = JSONDecoder()
        return try decoder.decode(JellyfinUploadProgressResponse.self, from: data)
    }

    /// Streams an MKV movie directly to the Jellyfin server via the Jellyboi File Upload plugin with auto-resume support
    public func uploadMovie(
        fileURL: URL,
        title: String,
        year: String,
        imdbId: String,
        libraryId: String?,
        serverPath: String? = nil,
        serverURL: String,
        apiKey: String,
        statusHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws {
        guard let baseURL = Self.normalizeURL(serverURL) else {
            throw JellyfinError.invalidServerURL
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw JellyfinError.uploadFailed("Source file does not exist: \(fileURL.path)")
        }

        let totalBytes: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            totalBytes = size
        } else {
            totalBytes = 0
        }

        let makeRequest: @Sendable (Int64) throws -> URLRequest = { offset in
            var components = URLComponents(url: baseURL.appendingPathComponent("FileToRemux/Upload/Movie"), resolvingAgainstBaseURL: false)
            var queryItems = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "year", value: year),
                URLQueryItem(name: "imdbId", value: imdbId),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "totalBytes", value: String(totalBytes))
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
            let remainingBytes = max(totalBytes - offset, 0)
            if remainingBytes > 0 {
                request.setValue(String(remainingBytes), forHTTPHeaderField: "Content-Length")
            }
            let key = apiKey.trimmingCharacters(in: .whitespaces)
            request.setValue(key, forHTTPHeaderField: "X-Emby-Token")
            request.setValue("MediaBrowser Token=\"\(key)\"", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 7200.0 // 2 hours for large remuxes
            return request
        }

        let probeProgress: @Sendable () async throws -> JellyfinUploadProgressResponse = {
            try await self.fetchUploadProgress(
                serverURL: serverURL,
                apiKey: apiKey,
                title: title,
                year: year,
                imdbId: imdbId,
                libraryId: libraryId,
                serverPath: serverPath
            )
        }

        try await performResumableUpload(
            fileURL: fileURL,
            totalBytes: totalBytes,
            makeRequest: makeRequest,
            probeProgress: probeProgress,
            statusHandler: statusHandler
        )
    }

    /// Streams an MKV TV episode directly to the Jellyfin server via the Jellyboi File Upload plugin with auto-resume support
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
        statusHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws {
        guard let baseURL = Self.normalizeURL(serverURL) else {
            throw JellyfinError.invalidServerURL
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw JellyfinError.uploadFailed("Source file does not exist: \(fileURL.path)")
        }

        let totalBytes: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            totalBytes = size
        } else {
            totalBytes = 0
        }

        let makeRequest: @Sendable (Int64) throws -> URLRequest = { offset in
            var components = URLComponents(url: baseURL.appendingPathComponent("FileToRemux/Upload/Episode"), resolvingAgainstBaseURL: false)
            var queryItems = [
                URLQueryItem(name: "seriesTitle", value: seriesTitle),
                URLQueryItem(name: "seriesYear", value: seriesYear),
                URLQueryItem(name: "seriesImdbId", value: seriesImdbId),
                URLQueryItem(name: "season", value: String(season)),
                URLQueryItem(name: "episode", value: String(episode)),
                URLQueryItem(name: "episodeTitle", value: episodeTitle),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "totalBytes", value: String(totalBytes))
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
            let remainingBytes = max(totalBytes - offset, 0)
            if remainingBytes > 0 {
                request.setValue(String(remainingBytes), forHTTPHeaderField: "Content-Length")
            }
            let key = apiKey.trimmingCharacters(in: .whitespaces)
            request.setValue(key, forHTTPHeaderField: "X-Emby-Token")
            request.setValue("MediaBrowser Token=\"\(key)\"", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 7200.0
            return request
        }

        let probeProgress: @Sendable () async throws -> JellyfinUploadProgressResponse = {
            try await self.fetchUploadProgress(
                serverURL: serverURL,
                apiKey: apiKey,
                seriesTitle: seriesTitle,
                seriesYear: seriesYear,
                seriesImdbId: seriesImdbId,
                season: season,
                episode: episode,
                episodeTitle: episodeTitle,
                libraryId: libraryId,
                serverPath: serverPath
            )
        }

        try await performResumableUpload(
            fileURL: fileURL,
            totalBytes: totalBytes,
            makeRequest: makeRequest,
            probeProgress: probeProgress,
            statusHandler: statusHandler
        )
    }

    /// Uploads a file stream starting from the server's current byte offset, automatically recovering
    /// from transient connection drops without restarting from byte 0.
    private func performResumableUpload(
        fileURL: URL,
        totalBytes: Int64,
        makeRequest: @Sendable (Int64) throws -> URLRequest,
        probeProgress: @Sendable () async throws -> JellyfinUploadProgressResponse,
        statusHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws {
        let maxAttempts = 10
        let retryDelays: [Duration] = [
            .seconds(2), .seconds(5), .seconds(10), .seconds(15), .seconds(30),
            .seconds(45), .seconds(60), .seconds(60), .seconds(60), .seconds(60)
        ]

        var attempt = 1
        var currentOffset: Int64 = 0

        // 1. Initial probe to discover existing progress on the server
        do {
            let progress = try await probeProgress()
            if progress.completed {
                statusHandler?(1.0, "Already completed on server")
                return
            }
            if progress.offset > 0 {
                currentOffset = min(progress.offset, totalBytes)
                let initialFraction = totalBytes > 0 ? Double(currentOffset) / Double(totalBytes) : 0.0
                statusHandler?(
                    initialFraction,
                    "Found existing upload on server: \(ByteCountFormatter.string(fromByteCount: currentOffset, countStyle: .file)) saved"
                )
            }
        } catch {
            // If the probe endpoint is not yet reachable or server is 1.0.6, default to 0 offset
            currentOffset = 0
        }

        while true {
            try Task.checkCancellation()

            do {
                if currentOffset > 0 {
                    let fraction = totalBytes > 0 ? Double(currentOffset) / Double(totalBytes) : 0.0
                    statusHandler?(
                        fraction,
                        "Resuming from \(ByteCountFormatter.string(fromByteCount: currentOffset, countStyle: .file))"
                    )
                }

                let request = try makeRequest(currentOffset)
                let (data, response) = try await Self.streamOnce(
                    request: request,
                    fromFile: fileURL,
                    offset: currentOffset,
                    totalBytes: totalBytes,
                    statusHandler: statusHandler
                )

                guard let http = response as? HTTPURLResponse else {
                    throw JellyfinError.uploadFailed("Invalid server response")
                }

                if !(200...299).contains(http.statusCode) {
                    // Check for 409 Conflict (e.g. server already has file or reported an offset conflict)
                    if http.statusCode == 409 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let completed = json["Completed"] as? Bool, completed {
                                statusHandler?(1.0, "Completed on server")
                                return
                            }
                            if let serverOffset = json["ServerOffset"] as? Int64, serverOffset != currentOffset {
                                currentOffset = serverOffset
                                continue
                            }
                        }
                    }

                    // Check for 499 (Client Closed Request / Paused by server or previous request)
                    if http.statusCode == 499 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let serverOffset = json["Offset"] as? Int64 {
                            currentOffset = min(serverOffset, totalBytes)
                        } else if let updatedProgress = try? await probeProgress(), !updatedProgress.completed {
                            currentOffset = min(updatedProgress.offset, totalBytes)
                        }
                        if attempt < maxAttempts {
                            let delay = retryDelays[min(attempt - 1, retryDelays.count - 1)]
                            statusHandler?(
                                totalBytes > 0 ? Double(currentOffset) / Double(totalBytes) : 0.0,
                                "Reconnecting upload. Retrying in \(delay)..."
                            )
                            try await Task.sleep(for: delay)
                            attempt += 1
                            continue
                        }
                    }

                    if http.statusCode == 401 || http.statusCode == 403 {
                        throw JellyfinError.unauthorized
                    }

                    if http.statusCode >= 500 && attempt < maxAttempts {
                        let delay = retryDelays[min(attempt - 1, retryDelays.count - 1)]
                        let errorMsg = Self.serverErrorMessage(from: data, statusCode: http.statusCode)
                        let statusText = errorMsg.isEmpty || errorMsg.starts(with: "Server returned HTTP")
                            ? "Server busy (HTTP \(http.statusCode)). Retrying in \(delay)..."
                            : "Server retry (\(errorMsg)). Retrying in \(delay)..."
                        statusHandler?(
                            totalBytes > 0 ? Double(currentOffset) / Double(totalBytes) : 0.0,
                            statusText
                        )
                        try await Task.sleep(for: delay)
                        attempt += 1

                        // Re-query server for latest received offset before retrying
                        if let updatedProgress = try? await probeProgress() {
                            if updatedProgress.completed {
                                statusHandler?(1.0, "Upload completed")
                                return
                            }
                            currentOffset = min(updatedProgress.offset, totalBytes)
                        }
                        continue
                    }

                    throw JellyfinError.uploadFailed(Self.serverErrorMessage(from: data, statusCode: http.statusCode))
                }

                // Check if server returned a 200 Partial upload response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["Status"] as? String,
                   status == "Partial",
                   let serverOffset = json["Offset"] as? Int64 {
                    currentOffset = min(serverOffset, totalBytes)
                    let fraction = totalBytes > 0 ? Double(currentOffset) / Double(totalBytes) : 0.0
                    statusHandler?(fraction, "Upload stream ended. Resuming...")
                    attempt = 1
                    continue
                }

                statusHandler?(1.0, "Upload completed")
                return
            } catch {
                try Task.checkCancellation()

                guard attempt < maxAttempts, Self.isTransientUploadError(error) else {
                    throw error
                }

                let delay = retryDelays[min(attempt - 1, retryDelays.count - 1)]
                let savedNotice = currentOffset > 0 ? " (\(ByteCountFormatter.string(fromByteCount: currentOffset, countStyle: .file)) saved)" : ""
                let fraction = totalBytes > 0 ? Double(currentOffset) / Double(totalBytes) : 0.0

                statusHandler?(
                    fraction,
                    "Connection lost. Retrying in \(delay)...\(savedNotice)"
                )

                try await Task.sleep(for: delay)
                attempt += 1

                // Query server for latest received offset before resuming
                if let updatedProgress = try? await probeProgress(), !updatedProgress.completed {
                    currentOffset = min(updatedProgress.offset, totalBytes)
                }
            }
        }
    }

    /// Streams a slice of the file starting at `offset` using URLSession with InputStream and custom delegate.
    private static func streamOnce(
        request: URLRequest,
        fromFile fileURL: URL,
        offset: Int64,
        totalBytes: Int64,
        statusHandler: (@Sendable (Double, String) -> Void)?
    ) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.waitsForConnectivity = false

        let delegate = StreamUploadDelegate(
            fileURL: fileURL,
            offset: offset,
            totalBytes: totalBytes,
            statusHandler: statusHandler
        )

        let attemptSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { attemptSession.invalidateAndCancel() }

        guard let stream = InputStream(url: fileURL) else {
            throw JellyfinError.uploadFailed("Could not open source file stream: \(fileURL.path)")
        }
        if offset > 0 {
            stream.setProperty(offset, forKey: Stream.PropertyKey.fileCurrentOffsetKey)
        }

        var mutableRequest = request
        mutableRequest.httpBodyStream = stream

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = attemptSession.dataTask(with: mutableRequest) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let response = response {
                        continuation.resume(returning: (data ?? Data(), response))
                    } else {
                        continuation.resume(throwing: JellyfinError.uploadFailed("No response received from server"))
                    }
                }
                delegate.activeTask = task
                task.resume()
            }
        } onCancel: {
            delegate.activeTask?.cancel()
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

    /// Forwards streaming progress and handles stream body recreation if URLSession challenges the connection.
    private final class StreamUploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let fileURL: URL
        let offset: Int64
        let totalBytes: Int64
        let statusHandler: (@Sendable (Double, String) -> Void)?
        weak var activeTask: URLSessionTask?

        init(
            fileURL: URL,
            offset: Int64,
            totalBytes: Int64,
            statusHandler: (@Sendable (Double, String) -> Void)?
        ) {
            self.fileURL = fileURL
            self.offset = offset
            self.totalBytes = totalBytes
            self.statusHandler = statusHandler
            super.init()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            guard totalBytes > 0 else { return }
            let overallSent = min(offset + totalBytesSent, totalBytes)
            let fraction = min(max(Double(overallSent) / Double(totalBytes), 0.0), 1.0)
            let sentStr = ByteCountFormatter.string(fromByteCount: overallSent, countStyle: .file)
            let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            statusHandler?(fraction, "Uploading (\(sentStr) / \(totalStr))")
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
            guard let stream = InputStream(url: fileURL) else {
                completionHandler(nil)
                return
            }
            if offset > 0 {
                stream.setProperty(offset, forKey: Stream.PropertyKey.fileCurrentOffsetKey)
            }
            completionHandler(stream)
        }
    }
}
