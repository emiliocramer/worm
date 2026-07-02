import Foundation

enum SpotifyConfigError: LocalizedError {
    case missingClientID
    case invalidRedirectURI(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Missing Spotify client ID. Set WORM_SPOTIFY_CLIENT_ID in Config/Secrets.xcconfig."
        case .invalidRedirectURI(let value):
            return "Invalid Spotify redirect URI: \(value)"
        }
    }
}

struct SpotifyAppConfiguration: Equatable {
    let clientID: String
    let redirectURI: URL

    static let infoClientIDKey = "WormSpotifyClientID"
    static let infoRedirectURIKey = "WormSpotifyRedirectURI"

    /// Every read scope Spotify exposes for user data. The goal of this node is
    /// to capture the most complete possible picture of the user's listening
    /// identity, so we request all of them up front.
    ///
    /// Note: a few of these (e.g. `user-read-email`) surface data that Spotify
    /// asks you to justify in the developer dashboard for extended quota.
    static let requiredScopes: [String] = [
        // Profile / account
        "user-read-private",
        "user-read-email",
        // Playback
        "user-read-currently-playing",
        "user-read-playback-state",
        "user-read-playback-position",
        "user-read-recently-played",
        // Taste
        "user-top-read",
        // Library
        "user-library-read",
        // Social graph
        "user-follow-read",
        // Playlists
        "playlist-read-private",
        "playlist-read-collaborative",
    ]

    var callbackScheme: String? {
        redirectURI.scheme
    }

    var isConfigured: Bool {
        !clientID.isEmpty
    }

    var missingConfigurationReason: String? {
        guard clientID.isEmpty else { return nil }
        return "Set `WORM_SPOTIFY_CLIENT_ID` in Config/Secrets.xcconfig, then register `\(redirectURI.absoluteString)` in your Spotify app dashboard."
    }

    static func current(bundle: Bundle) -> SpotifyAppConfiguration {
        let clientID = (bundle.object(forInfoDictionaryKey: infoClientIDKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let redirectValue = (bundle.object(forInfoDictionaryKey: infoRedirectURIKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "com.shibuya.worm.spotify-auth://oauth-callback"

        let redirectURI = URL(string: redirectValue)
            ?? URL(string: "com.shibuya.worm.spotify-auth://oauth-callback")!

        return SpotifyAppConfiguration(clientID: clientID, redirectURI: redirectURI)
    }

    func validate() throws {
        guard !clientID.isEmpty else { throw SpotifyConfigError.missingClientID }
        guard redirectURI.scheme?.isEmpty == false else {
            throw SpotifyConfigError.invalidRedirectURI(redirectURI.absoluteString)
        }
    }
}
