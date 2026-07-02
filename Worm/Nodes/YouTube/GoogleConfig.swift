import Foundation

enum GoogleConfigError: LocalizedError {
    case missingClientID
    case invalidRedirectURI(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Missing Google client ID. Set WORM_GOOGLE_CLIENT_ID in Config/Secrets.xcconfig."
        case .invalidRedirectURI(let value):
            return "Invalid Google redirect URI: \(value)"
        }
    }
}

struct GoogleAppConfiguration: Equatable {
    let clientID: String
    let redirectURI: URL

    static let infoClientIDKey = "WormGoogleClientID"
    static let infoRedirectURIKey = "WormGoogleRedirectURI"

    /// Google is the auth spine; YouTube is the first rich culture node on it.
    /// Keep this set narrow enough for review, but deep enough to read the full
    /// YouTube account surface available to a standard user token.
    static let requiredScopes: [String] = [
        "openid",
        "profile",
        "email",
        "https://www.googleapis.com/auth/youtube.readonly",
    ]

    var callbackScheme: String? {
        redirectURI.scheme
    }

    var isConfigured: Bool {
        !clientID.isEmpty
    }

    var missingConfigurationReason: String? {
        guard clientID.isEmpty else { return nil }
        return "Set `WORM_GOOGLE_CLIENT_ID` in Config/Secrets.xcconfig, then add the reversed client ID as a URL scheme for the iOS OAuth client."
    }

    static func current(bundle: Bundle) -> GoogleAppConfiguration {
        let clientID = (bundle.object(forInfoDictionaryKey: infoClientIDKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let derivedRedirectValue = defaultRedirectURIString(clientID: clientID)
            ?? "com.shibuya.worm.google-auth:/oauth2redirect"

        let redirectValue = (bundle.object(forInfoDictionaryKey: infoRedirectURIKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? derivedRedirectValue

        let redirectURI = URL(string: redirectValue)
            ?? URL(string: derivedRedirectValue)!

        return GoogleAppConfiguration(clientID: clientID, redirectURI: redirectURI)
    }

    private static func defaultRedirectURIString(clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let identifier = clientID.dropLast(suffix.count)
        guard !identifier.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(identifier):/oauth2redirect/google"
    }

    func validate() throws {
        guard !clientID.isEmpty else { throw GoogleConfigError.missingClientID }
        guard redirectURI.scheme?.isEmpty == false else {
            throw GoogleConfigError.invalidRedirectURI(redirectURI.absoluteString)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
