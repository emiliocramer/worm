import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import UIKit

private actor YouTubeSyncWorker {
    private static let pageSize = 50
    private static let maxSubscriptions = 5_000
    private static let maxActivities = 2_000
    private static let maxPlaylists = 1_000
    private static let maxPlaylistItemsTotal = 100_000
    private static let maxUploadItemsTotal = 50_000
    private static let maxLikedVideos = 10_000
    private static let maxEnrichedVideos = 50_000
    private static let maxEnrichedChannels = 10_000

    private let api = YouTubeWebAPI()

    func sync(
        accessToken token: String,
        grantedScopes: [String],
        progress: @escaping (String?) -> Void
    ) async throws -> YouTubeCultureNodeSnapshot {
        var limitations: [String] = [
            "YouTube Data API does not expose full watch history or Watch Later through this standard read-only connection.",
        ]

        progress("Reading Google identity...")
        let googleProfile = try? await api.fetchUserInfo(accessToken: token)

        progress("Reading YouTube channels...")
        let channels: [YTChannel] = await capture("channels", into: &limitations) {
            try await api.fetchMyChannels(accessToken: token).items
        } ?? []

        let regionCode = channels.first?.snippet?.country
            ?? Locale.current.region?.identifier
            ?? "US"

        progress("Reading video categories...")
        let categories: [YTVideoCategory] = await capture("video categories", into: &limitations) {
            try await api.fetchVideoCategories(accessToken: token, regionCode: regionCode).items
        } ?? []

        progress("Reading channel sections...")
        let channelSections: [YTChannelSection] = await capture("channel sections", into: &limitations) {
            try await allTokenPages(max: 500) { pageToken in
                let page = try await api.fetchChannelSections(accessToken: token, pageToken: pageToken)
                return (page.items, page.nextPageToken, page.pageInfo?.totalResults)
            }
        } ?? []

        progress("Reading subscriptions...")
        let subscriptions: [YTSubscription] = await capture("subscriptions", into: &limitations) {
            try await allTokenPages(max: Self.maxSubscriptions) { pageToken in
                let page = try await api.fetchSubscriptions(accessToken: token, pageToken: pageToken)
                return (page.items, page.nextPageToken, page.pageInfo?.totalResults)
            }
        } ?? []

        progress("Reading account activity...")
        let activities: [YTActivity] = await capture("activities", into: &limitations) {
            try await allTokenPages(max: Self.maxActivities) { pageToken in
                let page = try await api.fetchActivities(accessToken: token, pageToken: pageToken)
                return (page.items, page.nextPageToken, page.pageInfo?.totalResults)
            }
        } ?? []

        progress("Reading playlists...")
        let playlists: [YTPlaylist] = await capture("playlists", into: &limitations) {
            try await allTokenPages(max: Self.maxPlaylists) { pageToken in
                let page = try await api.fetchPlaylists(accessToken: token, pageToken: pageToken)
                return (page.items, page.nextPageToken, page.pageInfo?.totalResults)
            }
        } ?? []

        let playlistItemsByID = await hydratePlaylists(
            token: token,
            playlists: playlists,
            max: Self.maxPlaylistItemsTotal,
            limitations: &limitations,
            progress: progress
        )

        let uploadsPlaylistItemsByChannelID = await hydrateUploads(
            token: token,
            channels: channels,
            max: Self.maxUploadItemsTotal,
            limitations: &limitations,
            progress: progress
        )

        progress("Reading liked videos...")
        let likedVideos: [YTVideo] = await capture("liked videos", into: &limitations) {
            try await allTokenPages(max: Self.maxLikedVideos) { pageToken in
                let page = try await api.fetchLikedVideos(accessToken: token, pageToken: pageToken)
                return (page.items, page.nextPageToken, page.pageInfo?.totalResults)
            }
        } ?? []

        let enrichedVideosByID = await enrichVideos(
            token: token,
            ids: collectVideoIDs(
                likedVideos: likedVideos,
                playlistItemsByID: playlistItemsByID,
                uploadsPlaylistItemsByChannelID: uploadsPlaylistItemsByChannelID,
                activities: activities
            ),
            limitations: &limitations,
            progress: progress
        )

        let enrichedChannelsByID = await enrichChannels(
            token: token,
            ids: collectChannelIDs(
                channels: channels,
                subscriptions: subscriptions,
                playlists: playlists,
                activities: activities,
                videos: Array(enrichedVideosByID.values) + likedVideos
            ),
            limitations: &limitations,
            progress: progress
        )

        return YouTubeCultureNodeSnapshot(
            googleProfile: googleProfile,
            channels: channels,
            subscriptions: subscriptions,
            channelSections: channelSections,
            activities: activities,
            playlists: playlists,
            playlistItemsByID: playlistItemsByID,
            uploadsPlaylistItemsByChannelID: uploadsPlaylistItemsByChannelID,
            likedVideos: likedVideos,
            enrichedVideosByID: enrichedVideosByID,
            enrichedChannelsByID: enrichedChannelsByID,
            videoCategoriesByID: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }),
            grantedScopes: grantedScopes.sorted(),
            apiLimitations: Array(Set(limitations)).sorted(),
            lastSyncedAt: Date()
        )
    }

    private func hydratePlaylists(
        token: String,
        playlists: [YTPlaylist],
        max maxCount: Int,
        limitations: inout [String],
        progress: @escaping (String?) -> Void
    ) async -> [String: [YTPlaylistItem]] {
        var itemsByID: [String: [YTPlaylistItem]] = [:]
        var remaining = maxCount

        for (index, playlist) in playlists.enumerated() {
            if Task.isCancelled || remaining <= 0 { break }
            if shouldReport(index: index, total: playlists.count) {
                progress("Reading YouTube playlist \(index + 1)/\(playlists.count): \(playlist.snippet?.title ?? playlist.id)")
            }
            let items: [YTPlaylistItem] = await capture("playlist items for \(playlist.snippet?.title ?? playlist.id)", into: &limitations) {
                try await allTokenPages(max: remaining) { pageToken in
                    let page = try await api.fetchPlaylistItems(
                        accessToken: token,
                        playlistID: playlist.id,
                        pageToken: pageToken
                    )
                    return (page.items, page.nextPageToken, page.pageInfo?.totalResults)
                }
            } ?? []
            itemsByID[playlist.id] = items
            remaining -= items.count
        }

        return itemsByID
    }

    private func hydrateUploads(
        token: String,
        channels: [YTChannel],
        max maxCount: Int,
        limitations: inout [String],
        progress: @escaping (String?) -> Void
    ) async -> [String: [YTPlaylistItem]] {
        var itemsByChannel: [String: [YTPlaylistItem]] = [:]
        var remaining = maxCount
        let channelsWithUploads = channels.compactMap { channel -> (id: String, title: String, playlistID: String)? in
            guard let uploads = channel.contentDetails?.relatedPlaylists?.uploads else { return nil }
            return (channel.id, channel.snippet?.title ?? channel.id, uploads)
        }

        for (index, channel) in channelsWithUploads.enumerated() {
            if Task.isCancelled || remaining <= 0 { break }
            progress("Reading uploads \(index + 1)/\(channelsWithUploads.count): \(channel.title)")
            let items: [YTPlaylistItem] = await capture("uploads for \(channel.title)", into: &limitations) {
                try await allTokenPages(max: remaining) { pageToken in
                    let page = try await api.fetchPlaylistItems(
                        accessToken: token,
                        playlistID: channel.playlistID,
                        pageToken: pageToken
                    )
                    return (page.items, page.nextPageToken, page.pageInfo?.totalResults)
                }
            } ?? []
            itemsByChannel[channel.id] = items
            remaining -= items.count
        }

        return itemsByChannel
    }

    private func enrichVideos(
        token: String,
        ids: [String],
        limitations: inout [String],
        progress: @escaping (String?) -> Void
    ) async -> [String: YTVideo] {
        let ids = Array(ids.prefix(Self.maxEnrichedVideos))
        var videos: [String: YTVideo] = [:]
        let batches = ids.chunked(size: 50)
        for (index, batch) in batches.enumerated() {
            if Task.isCancelled { break }
            if index == 0 || (index + 1).isMultiple(of: 20) || (index + 1) == batches.count {
                progress("Enriching YouTube videos \(min((index + 1) * 50, ids.count))/\(ids.count)")
            }
            let items: [YTVideo] = await capture("video enrichment", into: &limitations) {
                try await api.fetchVideos(accessToken: token, ids: batch).items
            } ?? []
            for video in items {
                videos[video.id] = video
            }
        }
        return videos
    }

    private func enrichChannels(
        token: String,
        ids: [String],
        limitations: inout [String],
        progress: @escaping (String?) -> Void
    ) async -> [String: YTChannel] {
        let ids = Array(ids.prefix(Self.maxEnrichedChannels))
        var channels: [String: YTChannel] = [:]
        let batches = ids.chunked(size: 50)
        for (index, batch) in batches.enumerated() {
            if Task.isCancelled { break }
            if index == 0 || (index + 1).isMultiple(of: 20) || (index + 1) == batches.count {
                progress("Enriching YouTube channels \(min((index + 1) * 50, ids.count))/\(ids.count)")
            }
            let items: [YTChannel] = await capture("channel enrichment", into: &limitations) {
                try await api.fetchChannels(accessToken: token, ids: batch).items
            } ?? []
            for channel in items {
                channels[channel.id] = channel
            }
        }
        return channels
    }

    private func collectVideoIDs(
        likedVideos: [YTVideo],
        playlistItemsByID: [String: [YTPlaylistItem]],
        uploadsPlaylistItemsByChannelID: [String: [YTPlaylistItem]],
        activities: [YTActivity]
    ) -> [String] {
        var ids = Set<String>()
        likedVideos.forEach { ids.insert($0.id) }
        playlistItemsByID.values.flatMap { $0 }.compactMap(\.videoID).forEach { ids.insert($0) }
        uploadsPlaylistItemsByChannelID.values.flatMap { $0 }.compactMap(\.videoID).forEach { ids.insert($0) }
        activities.flatMap(activityVideoIDs).forEach { ids.insert($0) }
        return ids.sorted()
    }

    private func collectChannelIDs(
        channels: [YTChannel],
        subscriptions: [YTSubscription],
        playlists: [YTPlaylist],
        activities: [YTActivity],
        videos: [YTVideo]
    ) -> [String] {
        var ids = Set<String>()
        channels.map(\.id).forEach { ids.insert($0) }
        subscriptions.compactMap { $0.snippet?.resourceId?.channelId }.forEach { ids.insert($0) }
        subscriptions.compactMap { $0.snippet?.channelId }.forEach { ids.insert($0) }
        playlists.compactMap { $0.snippet?.channelId }.forEach { ids.insert($0) }
        activities.compactMap { $0.snippet?.channelId }.forEach { ids.insert($0) }
        videos.compactMap { $0.snippet?.channelId }.forEach { ids.insert($0) }
        return ids.sorted()
    }

    private func activityVideoIDs(_ activity: YTActivity) -> [String] {
        [
            activity.contentDetails?.upload?.videoId,
            activity.contentDetails?.like?.resourceId?.videoId,
            activity.contentDetails?.favorite?.resourceId?.videoId,
            activity.contentDetails?.playlistItem?.resourceId?.videoId,
            activity.contentDetails?.recommendation?.resourceId?.videoId,
            activity.contentDetails?.recommendation?.seedResourceId?.videoId,
            activity.contentDetails?.social?.resourceId?.videoId,
            activity.contentDetails?.bulletin?.resourceId?.videoId,
            activity.contentDetails?.channelItem?.resourceId?.videoId,
        ].compactMap { $0 }
    }

    private func allTokenPages<Item>(
        max maxCount: Int,
        fetch: (_ pageToken: String?) async throws -> (items: [Item], nextPageToken: String?, total: Int?)
    ) async throws -> [Item] {
        var all: [Item] = []
        var pageToken: String?
        while all.count < maxCount {
            try Task.checkCancellation()
            let page = try await fetch(pageToken)
            if page.items.isEmpty { break }
            all.append(contentsOf: page.items)
            pageToken = page.nextPageToken
            if pageToken == nil { break }
            if let total = page.total, all.count >= total { break }
        }
        return Array(all.prefix(maxCount))
    }

    private func capture<T>(
        _ label: String,
        into limitations: inout [String],
        work: () async throws -> T
    ) async -> T? {
        do {
            return try await work()
        } catch is CancellationError {
            return nil
        } catch {
            limitations.append("Could not read \(label): \(error.localizedDescription)")
            return nil
        }
    }

    private func shouldReport(index: Int, total: Int) -> Bool {
        index == 0 || (index + 1).isMultiple(of: 25) || index == total - 1
    }
}

/// Google is the auth spine. This node is the first Google-backed culture node:
/// YouTube subscriptions, liked videos, playlists, channel sections, activity,
/// uploads, and rich video/channel metadata. It is intentionally not a music
/// node. It captures media taste, creators, topics, references, formats, and
/// recurring culture signals that can steer any brain output.
@MainActor
@Observable
final class YouTubeCultureNode {
    // MARK: Observable state

    private(set) var isConfigured = false
    private(set) var isAuthorized = false
    private(set) var isAuthorizing = false
    private(set) var isSyncing = false
    private(set) var grantedScopes: [String] = []
    private(set) var syncProgress: String?
    private(set) var lastSyncedAt: Date?
    private(set) var lastErrorMessage: String?
    private(set) var configurationMessage: String?

    private(set) var googleProfile: GoogleUserInfo?
    private(set) var channels: [YTChannel] = []
    private(set) var subscriptions: [YTSubscription] = []
    private(set) var channelSections: [YTChannelSection] = []
    private(set) var activities: [YTActivity] = []
    private(set) var playlists: [YTPlaylist] = []
    private(set) var playlistItemsByID: [String: [YTPlaylistItem]] = [:]
    private(set) var uploadsPlaylistItemsByChannelID: [String: [YTPlaylistItem]] = [:]
    private(set) var likedVideos: [YTVideo] = []
    private(set) var enrichedVideosByID: [String: YTVideo] = [:]
    private(set) var enrichedChannelsByID: [String: YTChannel] = [:]
    private(set) var videoCategoriesByID: [String: YTVideoCategory] = [:]
    private(set) var apiLimitations: [String] = []

    // MARK: Private

    @ObservationIgnored private let config: GoogleAppConfiguration
    @ObservationIgnored private let tokenStore = GoogleTokenStore()
    @ObservationIgnored private let api = YouTubeWebAPI()
    @ObservationIgnored private let presentationContextProvider = GoogleAuthPresentationContextProvider()
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var tokens: GoogleAuthorizationTokens?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let syncWorker = YouTubeSyncWorker()
    @ObservationIgnored private let snapshotStore = SnapshotStore<YouTubeCultureNodeSnapshot>(filename: "youtube-culture-snapshot.json")

    init(config: GoogleAppConfiguration? = nil) {
        let resolved = config ?? GoogleAppConfiguration.current(bundle: .main)
        self.config = resolved
        isConfigured = resolved.isConfigured
        configurationMessage = resolved.missingConfigurationReason
        loadCachedSnapshot()
        if loadStoredTokensIfAvailable() || hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    var statusSummary: String {
        if !isConfigured { return configurationMessage ?? "Google is not configured." }
        if isAuthorizing { return "Connecting to Google..." }
        if isSyncing { return syncProgress ?? "Pulling YouTube culture..." }
        if isAuthorized, let name = googleProfile?.name { return "Connected as \(name)" }
        if isAuthorized, hasRestoredSnapshot { return "Restored YouTube culture snapshot" }
        return "YouTube not connected."
    }

    var callbackURIString: String { config.redirectURI.absoluteString }

    var playlistItemCount: Int {
        playlistItemsByID.values.reduce(0) { $0 + $1.count }
    }

    var uploadItemCount: Int {
        uploadsPlaylistItemsByChannelID.values.reduce(0) { $0 + $1.count }
    }

    // MARK: Lifecycle

    func restoreSessionIfPossible() async {
        isConfigured = config.isConfigured
        configurationMessage = config.missingConfigurationReason
        guard isConfigured else { return }

        loadCachedSnapshot()
        if loadStoredTokensIfAvailable() {
            isAuthorized = true
            if !hasRestoredSnapshot {
                await syncEverything()
            }
        } else if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    func connect() async {
        guard await requestAccess() else { return }
        // Sync unless we already restored a snapshot (fresh auth has none, so it
        // still syncs). Mirrors the original connect() behavior.
        if !hasRestoredSnapshot {
            await syncEverything()
        }
    }

    /// Acquire Google authorization only (reusing a stored session when
    /// possible), without the follow-on sync. Returns whether the node ended up
    /// authorized. The feed flow uses this so the heavy sync can run in the
    /// background instead of blocking the UI; `connect()` = this + `syncEverything()`.
    @discardableResult
    func requestAccess() async -> Bool {
        lastErrorMessage = nil
        guard isConfigured else {
            lastErrorMessage = configurationMessage ?? "Google is not configured."
            return false
        }

        if isAuthorized || loadStoredTokensIfAvailable() {
            isAuthorized = true
            return true
        }

        do {
            try config.validate()
            isAuthorizing = true
            let newTokens = try await acquireTokens()
            try tokenStore.save(newTokens)
            tokens = newTokens
            grantedScopes = newTokens.scopes.sorted()
            isAuthorized = true
            isAuthorizing = false
            return true
        } catch {
            isAuthorizing = false
            if (error as NSError).domain == ASWebAuthenticationSessionError.errorDomain,
               (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                lastErrorMessage = "Google authorization cancelled."
            } else {
                lastErrorMessage = error.localizedDescription
            }
            return false
        }
    }

    func disconnect() {
        syncTask?.cancel()
        syncTask = nil
        do {
            try tokenStore.delete()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        tokens = nil
        grantedScopes = []
        isAuthorized = false
        isAuthorizing = false
        isSyncing = false
        syncProgress = nil
        googleProfile = nil
        channels = []
        subscriptions = []
        channelSections = []
        activities = []
        playlists = []
        playlistItemsByID = [:]
        uploadsPlaylistItemsByChannelID = [:]
        likedVideos = []
        enrichedVideosByID = [:]
        enrichedChannelsByID = [:]
        videoCategoriesByID = [:]
        apiLimitations = []
        lastSyncedAt = nil
        snapshotStore.delete()
    }

    func syncEverything() async {
        guard isAuthorized else { return }
        if let syncTask {
            await syncTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            isSyncing = true
            defer {
                isSyncing = false
                syncProgress = nil
                syncTask = nil
            }
            do {
                try await runFullSync()
            } catch GoogleAPIError.unauthorized {
                do {
                    _ = try await refreshTokens()
                    try await runFullSync()
                } catch is CancellationError {
                    // User cancelled or disconnected mid-sync.
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            } catch is CancellationError {
                // User cancelled or disconnected mid-sync.
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        syncTask = task
        await task.value
    }

    // MARK: Snapshot

    private func loadCachedSnapshot() {
        guard let snapshot = snapshotStore.load() else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: YouTubeCultureNodeSnapshot) {
        googleProfile = snapshot.googleProfile
        channels = snapshot.channels
        subscriptions = snapshot.subscriptions
        channelSections = snapshot.channelSections
        activities = snapshot.activities
        playlists = snapshot.playlists
        playlistItemsByID = snapshot.playlistItemsByID
        uploadsPlaylistItemsByChannelID = snapshot.uploadsPlaylistItemsByChannelID
        likedVideos = snapshot.likedVideos
        enrichedVideosByID = snapshot.enrichedVideosByID
        enrichedChannelsByID = snapshot.enrichedChannelsByID
        videoCategoriesByID = snapshot.videoCategoriesByID
        grantedScopes = snapshot.grantedScopes
        apiLimitations = snapshot.apiLimitations
        lastSyncedAt = snapshot.lastSyncedAt
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    private func saveCachedSnapshot() {
        snapshotStore.save(
            YouTubeCultureNodeSnapshot(
                googleProfile: googleProfile,
                channels: channels,
                subscriptions: subscriptions,
                channelSections: channelSections,
                activities: activities,
                playlists: playlists,
                playlistItemsByID: playlistItemsByID,
                uploadsPlaylistItemsByChannelID: uploadsPlaylistItemsByChannelID,
                likedVideos: likedVideos,
                enrichedVideosByID: enrichedVideosByID,
                enrichedChannelsByID: enrichedChannelsByID,
                videoCategoriesByID: videoCategoriesByID,
                grantedScopes: grantedScopes,
                apiLimitations: apiLimitations,
                lastSyncedAt: lastSyncedAt
            )
        )
    }

    private var hasRestoredSnapshot: Bool {
        googleProfile != nil ||
            lastSyncedAt != nil ||
            !channels.isEmpty ||
            !subscriptions.isEmpty ||
            !playlists.isEmpty ||
            !playlistItemsByID.isEmpty ||
            !likedVideos.isEmpty
    }

    // MARK: Full sync

    private func runFullSync() async throws {
        let token = try await validAccessToken()
        lastErrorMessage = nil

        report("Preparing YouTube sync...")
        let snapshot = try await syncWorker.sync(accessToken: token, grantedScopes: grantedScopes) { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncing else { return }
                self.report(message)
            }
        }
        try Task.checkCancellation()
        apply(snapshot)
        saveCachedSnapshot()
        report(nil)
    }

    private func report(_ message: String?) {
        syncProgress = message
    }

    // MARK: Tokens

    private func loadStoredTokensIfAvailable() -> Bool {
        if tokens != nil { return true }
        if let stored = (try? tokenStore.load()) ?? nil {
            tokens = stored
            grantedScopes = stored.scopes.sorted()
            return true
        }
        return false
    }

    private func validAccessToken() async throws -> String {
        guard let tokens else { throw GoogleAPIError.unauthorized }
        if tokens.needsRefresh {
            return try await refreshTokens().accessToken
        }
        return tokens.accessToken
    }

    @discardableResult
    private func refreshTokens() async throws -> GoogleAuthorizationTokens {
        guard let tokens else { throw GoogleAPIError.unauthorized }
        guard !tokens.refreshToken.isEmpty else { throw GoogleAPIError.missingRefreshToken }

        let response = try await api.refreshTokens(config: config, refreshToken: tokens.refreshToken)
        let refreshed = tokens.refreshed(with: response)
        try tokenStore.save(refreshed)
        self.tokens = refreshed
        grantedScopes = refreshed.scopes.sorted()
        isAuthorized = true
        return refreshed
    }

    // MARK: PKCE authorization

    private func acquireTokens() async throws -> GoogleAuthorizationTokens {
        let result = try await authorizeWithPKCE()
        let response = try await api.exchangeAuthorizationCode(
            config: config,
            code: result.authorizationCode,
            codeVerifier: result.codeVerifier
        )
        let tokens = GoogleAuthorizationTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? "",
            tokenType: response.tokenType,
            scopes: response.scopeList.isEmpty ? GoogleAppConfiguration.requiredScopes : response.scopeList,
            expirationDate: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        guard !tokens.refreshToken.isEmpty else { throw GoogleAPIError.missingRefreshToken }
        return tokens
    }

    private func authorizeWithPKCE() async throws -> GoogleAuthorizationResult {
        let codeVerifier = Self.randomURLSafeString(length: 96)
        let state = Self.randomURLSafeString(length: 32)
        let codeChallenge = Self.codeChallenge(for: codeVerifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: GoogleAppConfiguration.requiredScopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard let url = components.url, let callbackScheme = config.callbackScheme else {
            throw GoogleConfigError.invalidRedirectURI(config.redirectURI.absoluteString)
        }

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleAPIError.invalidResponse)
                }
            }
            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuation.resume(throwing: GoogleAPIError.invalidResponse)
            }
        }

        authSession = nil

        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let items = components.queryItems
        else {
            throw GoogleAPIError.invalidResponse
        }

        let returnedState = items.first(where: { $0.name == "state" })?.value
        let code = items.first(where: { $0.name == "code" })?.value
        let authError = items.first(where: { $0.name == "error" })?.value

        if let authError {
            throw GoogleAPIError.http(statusCode: 400, message: authError)
        }
        guard returnedState == state, let code, !code.isEmpty else {
            throw GoogleAPIError.invalidResponse
        }

        return GoogleAuthorizationResult(authorizationCode: code, codeVerifier: codeVerifier)
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: max(length, 32))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64URLEncodedString().prefix(length).description
    }
}

private struct GoogleAuthorizationResult {
    let authorizationCode: String
    let codeVerifier: String
}

private final class GoogleAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Array where Element == String {
    func chunked(size: Int) -> [[String]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
