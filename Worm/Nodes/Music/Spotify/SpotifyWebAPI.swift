import Foundation
import Security

enum SpotifyAPIError: LocalizedError {
    case unauthorized
    case invalidResponse
    case transport(Error)
    case http(statusCode: Int, message: String?)
    case decoding(Error)
    case missingRefreshToken
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Spotify authorization expired."
        case .invalidResponse:
            return "Spotify returned an invalid response."
        case .transport(let error):
            return error.localizedDescription
        case .http(let statusCode, let message):
            return message?.isEmpty == false ? "Spotify HTTP \(statusCode): \(message!)" : "Spotify HTTP \(statusCode)"
        case .decoding(let error):
            return "Spotify decode failure: \(error.localizedDescription)"
        case .missingRefreshToken:
            return "Missing Spotify refresh token."
        case .keychain(let status):
            return "Spotify keychain failure (\(status))."
        }
    }
}

// MARK: - Token storage

struct SpotifyTokenStore {
    private static let service = "com.shibuya.worm.spotify"
    private static let account = "default-session"

    func load() throws -> SpotifyAuthorizationTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SpotifyAPIError.keychain(status)
        }
        guard let data = item as? Data else {
            throw SpotifyAPIError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(SpotifyAuthorizationTokens.self, from: data)
        } catch {
            throw SpotifyAPIError.decoding(error)
        }
    }

    func save(_ tokens: SpotifyAuthorizationTokens) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(tokens)
        } catch {
            throw SpotifyAPIError.decoding(error)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw SpotifyAPIError.keychain(updateStatus)
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        // Survive device locks / background relaunch while still being protected
        // until first unlock after boot.
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw SpotifyAPIError.keychain(insertStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return
        }
        throw SpotifyAPIError.keychain(status)
    }
}

// MARK: - Web API

struct SpotifyWebAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = SpotifyWebAPI.defaultSession) {
        self.session = session
        self.decoder = SpotifyWebAPI.defaultDecoder
    }

    // MARK: Token exchange

    func exchangeAuthorizationCode(
        config: SpotifyAppConfiguration,
        code: String,
        codeVerifier: String
    ) async throws -> SpotifyTokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = urlEncodedBody([
            "client_id": config.clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI.absoluteString,
            "code_verifier": codeVerifier,
        ])

        return try await decode(SpotifyTokenResponse.self, from: request)
    }

    func refreshTokens(
        config: SpotifyAppConfiguration,
        refreshToken: String
    ) async throws -> SpotifyTokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = urlEncodedBody([
            "client_id": config.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        return try await decode(SpotifyTokenResponse.self, from: request)
    }

    // MARK: Profile & playback

    func fetchCurrentUser(accessToken: String) async throws -> SpotifyUserProfile {
        try await decode(SpotifyUserProfile.self, from: authorizedRequest(path: "/me", accessToken: accessToken))
    }

    func fetchCurrentlyPlaying(accessToken: String) async throws -> SpotifyCurrentPlayback? {
        try await decodeOptional(
            SpotifyCurrentPlayback.self,
            from: authorizedRequest(path: "/me/player/currently-playing", accessToken: accessToken)
        )
    }

    func fetchPlaybackState(accessToken: String) async throws -> SpotifyCurrentPlayback? {
        try await decodeOptional(
            SpotifyCurrentPlayback.self,
            from: authorizedRequest(path: "/me/player", accessToken: accessToken)
        )
    }

    func fetchAvailableDevices(accessToken: String) async throws -> SpotifyDevicesResponse {
        try await decode(
            SpotifyDevicesResponse.self,
            from: authorizedRequest(path: "/me/player/devices", accessToken: accessToken)
        )
    }

    func fetchQueue(accessToken: String) async throws -> SpotifyQueueResponse {
        try await decode(
            SpotifyQueueResponse.self,
            from: authorizedRequest(path: "/me/player/queue", accessToken: accessToken)
        )
    }

    // MARK: Taste

    func fetchTopTracks(
        accessToken: String,
        limit: Int = 50,
        offset: Int = 0,
        timeRange: String = "medium_term"
    ) async throws -> SpotifyPagedResponse<SpotifyTrack> {
        try await decode(
            SpotifyPagedResponse<SpotifyTrack>.self,
            from: authorizedRequest(
                path: "/me/top/tracks",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "limit", value: "\(clamp(limit))"),
                    URLQueryItem(name: "offset", value: "\(max(offset, 0))"),
                    URLQueryItem(name: "time_range", value: timeRange),
                ]
            )
        )
    }

    func fetchTopArtists(
        accessToken: String,
        limit: Int = 50,
        offset: Int = 0,
        timeRange: String = "medium_term"
    ) async throws -> SpotifyPagedResponse<SpotifyArtist> {
        try await decode(
            SpotifyPagedResponse<SpotifyArtist>.self,
            from: authorizedRequest(
                path: "/me/top/artists",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "limit", value: "\(clamp(limit))"),
                    URLQueryItem(name: "offset", value: "\(max(offset, 0))"),
                    URLQueryItem(name: "time_range", value: timeRange),
                ]
            )
        )
    }

    func fetchRecentlyPlayed(accessToken: String, limit: Int = 50) async throws -> SpotifyRecentlyPlayedResponse {
        try await decode(
            SpotifyRecentlyPlayedResponse.self,
            from: authorizedRequest(
                path: "/me/player/recently-played",
                accessToken: accessToken,
                queryItems: [URLQueryItem(name: "limit", value: "\(clamp(limit))")]
            )
        )
    }

    // MARK: Library

    func fetchSavedTracks(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifyPagedResponse<SpotifySavedTrack> {
        try await pagedRequest("/me/tracks", accessToken: accessToken, limit: limit, offset: offset)
    }

    func fetchSavedAlbums(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifyPagedResponse<SpotifySavedAlbum> {
        try await pagedRequest("/me/albums", accessToken: accessToken, limit: limit, offset: offset)
    }

    func fetchSavedShows(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifyPagedResponse<SpotifySavedShow> {
        try await pagedRequest("/me/shows", accessToken: accessToken, limit: limit, offset: offset)
    }

    func fetchSavedEpisodes(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifyPagedResponse<SpotifySavedEpisode> {
        try await pagedRequest("/me/episodes", accessToken: accessToken, limit: limit, offset: offset)
    }

    func fetchSavedAudiobooks(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifyPagedResponse<SpotifyAudiobook> {
        try await pagedRequest("/me/audiobooks", accessToken: accessToken, limit: limit, offset: offset)
    }

    func fetchAlbumTracks(
        accessToken: String,
        albumID: String,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SpotifyPagedResponse<SpotifyTrack> {
        try await pagedRequest("/albums/\(albumID)/tracks", accessToken: accessToken, limit: limit, offset: offset)
    }

    func fetchShowEpisodes(
        accessToken: String,
        showID: String,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SpotifyPagedResponse<SpotifyEpisode> {
        try await pagedRequest("/shows/\(showID)/episodes", accessToken: accessToken, limit: limit, offset: offset)
    }

    func fetchAudiobookChapters(
        accessToken: String,
        audiobookID: String,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SpotifyPagedResponse<SpotifyChapter> {
        try await pagedRequest("/audiobooks/\(audiobookID)/chapters", accessToken: accessToken, limit: limit, offset: offset)
    }

    // MARK: Social

    func fetchFollowedArtists(accessToken: String, after: String?, limit: Int = 50) async throws -> SpotifyFollowedArtistsResponse {
        var items = [
            URLQueryItem(name: "type", value: "artist"),
            URLQueryItem(name: "limit", value: "\(clamp(limit))"),
        ]
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        return try await decode(
            SpotifyFollowedArtistsResponse.self,
            from: authorizedRequest(path: "/me/following", accessToken: accessToken, queryItems: items)
        )
    }

    // MARK: Playlists

    func fetchPlaylists(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifyPagedResponse<SpotifyPlaylist> {
        try await pagedRequest("/me/playlists", accessToken: accessToken, limit: limit, offset: offset)
    }

    func fetchPlaylistItems(
        accessToken: String,
        playlistID: String,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SpotifyPagedResponse<SpotifyPlaylistItem> {
        try await decode(
            SpotifyPagedResponse<SpotifyPlaylistItem>.self,
            from: authorizedRequest(
                path: "/playlists/\(playlistID)/tracks",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "limit", value: "\(clamp(limit))"),
                    URLQueryItem(name: "offset", value: "\(max(offset, 0))"),
                    URLQueryItem(name: "additional_types", value: "track"),
                ]
            )
        )
    }

    // MARK: Catalog Search

    func searchTracks(accessToken: String, query: String, limit: Int = 10) async throws -> SpotifyTrackSearchResponse {
        try await decode(
            SpotifyTrackSearchResponse.self,
            from: authorizedRequest(
                path: "/search",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "type", value: "track"),
                    URLQueryItem(name: "limit", value: "\(clamp(limit))"),
                ]
            )
        )
    }

    // MARK: - Request building

    private func pagedRequest<Item: Decodable>(
        _ path: String,
        accessToken: String,
        limit: Int,
        offset: Int
    ) async throws -> SpotifyPagedResponse<Item> {
        try await decode(
            SpotifyPagedResponse<Item>.self,
            from: authorizedRequest(
                path: path,
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "limit", value: "\(clamp(limit))"),
                    URLQueryItem(name: "offset", value: "\(max(offset, 0))"),
                ]
            )
        )
    }

    private func authorizedRequest(
        path: String,
        accessToken: String,
        queryItems: [URLQueryItem] = []
    ) -> URLRequest {
        var components = URLComponents(string: "https://api.spotify.com/v1\(path)")!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func clamp(_ limit: Int) -> Int {
        min(max(limit, 1), 50)
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        if http.statusCode == 401 {
            throw SpotifyAPIError.unauthorized
        }
        if !(200..<300).contains(http.statusCode) {
            throw SpotifyAPIError.http(statusCode: http.statusCode, message: responseMessage(from: data))
        }
        return try decode(type, from: data)
    }

    /// Variant for endpoints that return 204 (No Content) when nothing is active,
    /// e.g. playback endpoints.
    private func decodeOptional<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T? {
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        if http.statusCode == 204 {
            return nil
        }
        if http.statusCode == 401 {
            throw SpotifyAPIError.unauthorized
        }
        if !(200..<300).contains(http.statusCode) {
            throw SpotifyAPIError.http(statusCode: http.statusCode, message: responseMessage(from: data))
        }
        return try decode(type, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SpotifyAPIError.decoding(error)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw SpotifyAPIError.transport(error)
        }
    }

    private func responseMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let message = object["error_description"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == true ? nil : text
    }

    private func urlEncodedBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static let defaultDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
}
