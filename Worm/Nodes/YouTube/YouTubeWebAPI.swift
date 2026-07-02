import Foundation
import Security

enum GoogleAPIError: LocalizedError {
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
            return "Google authorization expired."
        case .invalidResponse:
            return "Google returned an invalid response."
        case .transport(let error):
            return error.localizedDescription
        case .http(let statusCode, let message):
            return message?.isEmpty == false ? "Google HTTP \(statusCode): \(message!)" : "Google HTTP \(statusCode)"
        case .decoding(let error):
            return "Google decode failure: \(error.localizedDescription)"
        case .missingRefreshToken:
            return "Missing Google refresh token."
        case .keychain(let status):
            return "Google keychain failure (\(status))."
        }
    }
}

// MARK: - Token storage

struct GoogleTokenStore {
    private static let service = "com.shibuya.worm.google"
    private static let account = "default-session"

    func load() throws -> GoogleAuthorizationTokens? {
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
            throw GoogleAPIError.keychain(status)
        }
        guard let data = item as? Data else {
            throw GoogleAPIError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(GoogleAuthorizationTokens.self, from: data)
        } catch {
            throw GoogleAPIError.decoding(error)
        }
    }

    func save(_ tokens: GoogleAuthorizationTokens) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(tokens)
        } catch {
            throw GoogleAPIError.decoding(error)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw GoogleAPIError.keychain(updateStatus)
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw GoogleAPIError.keychain(insertStatus)
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
        throw GoogleAPIError.keychain(status)
    }
}

// MARK: - Web API

struct YouTubeWebAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = YouTubeWebAPI.defaultSession) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: Token exchange

    func exchangeAuthorizationCode(
        config: GoogleAppConfiguration,
        code: String,
        codeVerifier: String
    ) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
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

        return try await decode(GoogleTokenResponse.self, from: request)
    }

    func refreshTokens(
        config: GoogleAppConfiguration,
        refreshToken: String
    ) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = urlEncodedBody([
            "client_id": config.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        return try await decode(GoogleTokenResponse.self, from: request)
    }

    // MARK: Google identity

    func fetchUserInfo(accessToken: String) async throws -> GoogleUserInfo {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decode(GoogleUserInfo.self, from: request)
    }

    // MARK: YouTube account surface

    func fetchMyChannels(accessToken: String) async throws -> YTPagedResponse<YTChannel> {
        try await decode(
            YTPagedResponse<YTChannel>.self,
            from: authorizedRequest(
                path: "/channels",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "part", value: channelParts),
                    URLQueryItem(name: "mine", value: "true"),
                    URLQueryItem(name: "maxResults", value: "50"),
                ]
            )
        )
    }

    func fetchChannelSections(
        accessToken: String,
        pageToken: String? = nil
    ) async throws -> YTPagedResponse<YTChannelSection> {
        var queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails,localizations"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await decode(
            YTPagedResponse<YTChannelSection>.self,
            from: authorizedRequest(path: "/channelSections", accessToken: accessToken, queryItems: queryItems)
        )
    }

    func fetchSubscriptions(
        accessToken: String,
        pageToken: String? = nil
    ) async throws -> YTPagedResponse<YTSubscription> {
        var queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails,subscriberSnippet"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "order", value: "alphabetical"),
        ]
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await decode(
            YTPagedResponse<YTSubscription>.self,
            from: authorizedRequest(path: "/subscriptions", accessToken: accessToken, queryItems: queryItems)
        )
    }

    func fetchActivities(
        accessToken: String,
        pageToken: String? = nil
    ) async throws -> YTPagedResponse<YTActivity> {
        var queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await decode(
            YTPagedResponse<YTActivity>.self,
            from: authorizedRequest(path: "/activities", accessToken: accessToken, queryItems: queryItems)
        )
    }

    func fetchPlaylists(
        accessToken: String,
        pageToken: String? = nil
    ) async throws -> YTPagedResponse<YTPlaylist> {
        var queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails,status,player,localizations"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await decode(
            YTPagedResponse<YTPlaylist>.self,
            from: authorizedRequest(path: "/playlists", accessToken: accessToken, queryItems: queryItems)
        )
    }

    func fetchPlaylistItems(
        accessToken: String,
        playlistID: String,
        pageToken: String? = nil
    ) async throws -> YTPagedResponse<YTPlaylistItem> {
        var queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails,status"),
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await decode(
            YTPagedResponse<YTPlaylistItem>.self,
            from: authorizedRequest(path: "/playlistItems", accessToken: accessToken, queryItems: queryItems)
        )
    }

    func fetchLikedVideos(
        accessToken: String,
        pageToken: String? = nil
    ) async throws -> YTPagedResponse<YTVideo> {
        var queryItems = [
            URLQueryItem(name: "part", value: videoParts),
            URLQueryItem(name: "myRating", value: "like"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await decode(
            YTPagedResponse<YTVideo>.self,
            from: authorizedRequest(path: "/videos", accessToken: accessToken, queryItems: queryItems)
        )
    }

    func fetchVideos(accessToken: String, ids: [String]) async throws -> YTPagedResponse<YTVideo> {
        try await decode(
            YTPagedResponse<YTVideo>.self,
            from: authorizedRequest(
                path: "/videos",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "part", value: videoParts),
                    URLQueryItem(name: "id", value: ids.joined(separator: ",")),
                    URLQueryItem(name: "maxResults", value: "50"),
                ]
            )
        )
    }

    func fetchChannels(accessToken: String, ids: [String]) async throws -> YTPagedResponse<YTChannel> {
        try await decode(
            YTPagedResponse<YTChannel>.self,
            from: authorizedRequest(
                path: "/channels",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "part", value: channelParts),
                    URLQueryItem(name: "id", value: ids.joined(separator: ",")),
                    URLQueryItem(name: "maxResults", value: "50"),
                ]
            )
        )
    }

    func fetchVideoCategories(accessToken: String, regionCode: String) async throws -> YTPagedResponse<YTVideoCategory> {
        try await decode(
            YTPagedResponse<YTVideoCategory>.self,
            from: authorizedRequest(
                path: "/videoCategories",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "part", value: "snippet"),
                    URLQueryItem(name: "regionCode", value: regionCode),
                ]
            )
        )
    }

    // MARK: - Request building

    private func authorizedRequest(
        path: String,
        accessToken: String,
        queryItems: [URLQueryItem]
    ) -> URLRequest {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3\(path)")!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleAPIError.invalidResponse
        }
        if http.statusCode == 401 {
            throw GoogleAPIError.unauthorized
        }
        if !(200..<300).contains(http.statusCode) {
            throw GoogleAPIError.http(statusCode: http.statusCode, message: responseMessage(from: data))
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw GoogleAPIError.decoding(error)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw GoogleAPIError.transport(error)
        }
    }

    private func responseMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let message = error["message"] as? String { return message }
                if let description = error["error_description"] as? String { return description }
            }
            if let message = object["error_description"] as? String { return message }
            if let message = object["message"] as? String { return message }
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

    private var channelParts: String {
        "snippet,contentDetails,statistics,topicDetails,status,brandingSettings,localizations"
    }

    private var videoParts: String {
        "snippet,contentDetails,status,statistics,topicDetails,recordingDetails,liveStreamingDetails,player,localizations,paidProductPlacementDetails"
    }

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 90
        return URLSession(configuration: config)
    }()
}
