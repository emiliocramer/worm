import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import UIKit

private actor SpotifySyncWorker {
    private static let pageSize = 50
    private static let maxSavedTracks = 10_000
    private static let maxSavedAlbums = 2_000
    private static let maxSavedShows = 1_000
    private static let maxSavedEpisodes = 2_000
    private static let maxSavedAudiobooks = 1_000
    private static let maxSavedAlbumTracksTotal = 50_000
    private static let maxSavedShowEpisodesTotal = 50_000
    private static let maxSavedAudiobookChaptersTotal = 20_000
    private static let maxFollowedArtists = 2_000
    private static let maxPlaylists = 500
    private static let maxPlaylistTracksTotal = 50_000
    private static let topItemsPerRange = 50

    private let api = SpotifyWebAPI()

    func sync(
        accessToken token: String,
        grantedScopes: [String],
        progress: @escaping (String?) -> Void
    ) async throws -> SpotifyNodeSnapshot {
        let scopes = Set(grantedScopes)

        progress("Reading profile…")
        let profile = try await api.fetchCurrentUser(accessToken: token)

        var topTracksShort: [SpotifyTrack] = []
        var topTracksMedium: [SpotifyTrack] = []
        var topTracksLong: [SpotifyTrack] = []
        var topArtistsShort: [SpotifyArtist] = []
        var topArtistsMedium: [SpotifyArtist] = []
        var topArtistsLong: [SpotifyArtist] = []
        if scopes.contains("user-top-read") {
            progress("Reading top tracks & artists…")
            topArtistsShort = try await allTopArtists(token: token, range: "short_term")
            topTracksShort = try await allTopTracks(token: token, range: "short_term")
            topArtistsMedium = try await allTopArtists(token: token, range: "medium_term")
            topTracksMedium = try await allTopTracks(token: token, range: "medium_term")
            topArtistsLong = try await allTopArtists(token: token, range: "long_term")
            topTracksLong = try await allTopTracks(token: token, range: "long_term")
        }

        progress("Reading playlists…")
        let playlists = try await allPages(max: Self.maxPlaylists) { offset in
            let page = try await api.fetchPlaylists(accessToken: token, limit: Self.pageSize, offset: offset)
            return (page.items, page.next, page.total)
        }

        progress("Reading playback…")
        let currentlyPlaying = try? await api.fetchCurrentlyPlaying(accessToken: token)
        let playbackState = try? await api.fetchPlaybackState(accessToken: token)
        let availableDevices = (try? await api.fetchAvailableDevices(accessToken: token).devices) ?? []
        let queue = try? await api.fetchQueue(accessToken: token)

        var recentlyPlayed: [SpotifyRecentlyPlayedItem] = []
        if scopes.contains("user-read-recently-played") {
            progress("Reading recently played…")
            recentlyPlayed = try await dedupedRecentlyPlayed(token: token)
        }

        var savedTracks: [SpotifySavedTrack] = []
        var savedAlbums: [SpotifySavedAlbum] = []
        var savedShows: [SpotifySavedShow] = []
        var savedEpisodes: [SpotifySavedEpisode] = []
        var savedAudiobooks: [SpotifyAudiobook] = []
        var savedAlbumTracksByID: [String: [SpotifyTrack]] = [:]
        var savedShowEpisodesByID: [String: [SpotifyEpisode]] = [:]
        var savedAudiobookChaptersByID: [String: [SpotifyChapter]] = [:]
        if scopes.contains("user-library-read") {
            progress("Reading saved tracks…")
            savedTracks = try await allPages(max: Self.maxSavedTracks) { offset in
                let page = try await api.fetchSavedTracks(accessToken: token, limit: Self.pageSize, offset: offset)
                return (page.items, page.next, page.total)
            }
            progress("Reading saved albums…")
            savedAlbums = try await allPages(max: Self.maxSavedAlbums) { offset in
                let page = try await api.fetchSavedAlbums(accessToken: token, limit: Self.pageSize, offset: offset)
                return (page.items, page.next, page.total)
            }
            progress("Reading saved shows…")
            savedShows = try await allPages(max: Self.maxSavedShows) { offset in
                let page = try await api.fetchSavedShows(accessToken: token, limit: Self.pageSize, offset: offset)
                return (page.items, page.next, page.total)
            }
            progress("Reading saved episodes…")
            savedEpisodes = try await allPages(max: Self.maxSavedEpisodes) { offset in
                let page = try await api.fetchSavedEpisodes(accessToken: token, limit: Self.pageSize, offset: offset)
                return (page.items, page.next, page.total)
            }
            progress("Reading saved audiobooks…")
            savedAudiobooks = (try? await allPages(max: Self.maxSavedAudiobooks) { offset in
                let page = try await api.fetchSavedAudiobooks(accessToken: token, limit: Self.pageSize, offset: offset)
                return (page.items, page.next, page.total)
            }) ?? []

            let children = await hydrateSavedLibraryChildren(
                token: token,
                savedAlbums: savedAlbums,
                savedShows: savedShows,
                savedAudiobooks: savedAudiobooks,
                progress: progress
            )
            savedAlbumTracksByID = children.albumTracks
            savedShowEpisodesByID = children.showEpisodes
            savedAudiobookChaptersByID = children.audiobookChapters
        }

        var followedArtists: [SpotifyArtist] = []
        if scopes.contains("user-follow-read") {
            progress("Reading followed artists…")
            followedArtists = try await allFollowedArtists(token: token)
        }

        let playlistItemsByID = try await hydratePlaylists(token: token, playlists: playlists, progress: progress)

        return SpotifyNodeSnapshot(
            profile: profile,
            currentlyPlaying: currentlyPlaying,
            playbackState: playbackState,
            availableDevices: availableDevices,
            queue: queue,
            recentlyPlayed: recentlyPlayed,
            topTracksShort: topTracksShort,
            topTracksMedium: topTracksMedium,
            topTracksLong: topTracksLong,
            topArtistsShort: topArtistsShort,
            topArtistsMedium: topArtistsMedium,
            topArtistsLong: topArtistsLong,
            savedTracks: savedTracks,
            savedAlbums: savedAlbums,
            savedShows: savedShows,
            savedEpisodes: savedEpisodes,
            savedAudiobooks: savedAudiobooks,
            savedAlbumTracksByID: savedAlbumTracksByID,
            savedShowEpisodesByID: savedShowEpisodesByID,
            savedAudiobookChaptersByID: savedAudiobookChaptersByID,
            followedArtists: followedArtists,
            playlists: playlists,
            playlistItemsByID: playlistItemsByID,
            grantedScopes: grantedScopes.sorted(),
            lastSyncedAt: Date()
        )
    }

    private func dedupedRecentlyPlayed(token: String) async throws -> [SpotifyRecentlyPlayedItem] {
        let response = try await api.fetchRecentlyPlayed(accessToken: token, limit: Self.pageSize)
        var seen = Set<String>()
        return response.items.filter { seen.insert($0.id).inserted }
    }

    private func allTopTracks(token: String, range: String) async throws -> [SpotifyTrack] {
        try await allPages(max: Self.topItemsPerRange) { offset in
            let page = try await api.fetchTopTracks(accessToken: token, limit: Self.pageSize, offset: offset, timeRange: range)
            return (page.items, page.next, page.total)
        }
    }

    private func allTopArtists(token: String, range: String) async throws -> [SpotifyArtist] {
        try await allPages(max: Self.topItemsPerRange) { offset in
            let page = try await api.fetchTopArtists(accessToken: token, limit: Self.pageSize, offset: offset, timeRange: range)
            return (page.items, page.next, page.total)
        }
    }

    private func allFollowedArtists(token: String) async throws -> [SpotifyArtist] {
        var all: [SpotifyArtist] = []
        var after: String?
        repeat {
            try Task.checkCancellation()
            let response = try await api.fetchFollowedArtists(accessToken: token, after: after, limit: Self.pageSize)
            all.append(contentsOf: response.artists.items)
            after = response.artists.cursors?.after
            if response.artists.next == nil || after == nil { break }
        } while all.count < Self.maxFollowedArtists
        return Array(all.prefix(Self.maxFollowedArtists))
    }

    private func hydratePlaylists(
        token: String,
        playlists: [SpotifyPlaylist],
        progress: @escaping (String?) -> Void
    ) async throws -> [String: [SpotifyPlaylistItem]] {
        var itemsByID: [String: [SpotifyPlaylistItem]] = [:]
        var remaining = Self.maxPlaylistTracksTotal

        for (index, playlist) in playlists.enumerated() {
            try Task.checkCancellation()
            guard remaining > 0 else { break }
            if shouldReport(index: index, total: playlists.count) {
                progress("Reading playlist \(index + 1)/\(playlists.count): \(playlist.name)")
            }
            let items = try await allPages(max: remaining) { offset in
                let page = try await api.fetchPlaylistItems(
                    accessToken: token,
                    playlistID: playlist.id,
                    limit: Self.pageSize,
                    offset: offset
                )
                return (page.items, page.next, page.total)
            }
            itemsByID[playlist.id] = items
            remaining -= items.count
        }
        return itemsByID
    }

    private func hydrateSavedLibraryChildren(
        token: String,
        savedAlbums: [SpotifySavedAlbum],
        savedShows: [SpotifySavedShow],
        savedAudiobooks: [SpotifyAudiobook],
        progress: @escaping (String?) -> Void
    ) async -> (
        albumTracks: [String: [SpotifyTrack]],
        showEpisodes: [String: [SpotifyEpisode]],
        audiobookChapters: [String: [SpotifyChapter]]
    ) {
        let albumTracks = await hydrateChildren(
            label: "saved album",
            containers: savedAlbums,
            containerID: { $0.album.id },
            containerName: { $0.album.name },
            max: Self.maxSavedAlbumTracksTotal,
            progress: progress
        ) { albumID, offset in
            let page = try await api.fetchAlbumTracks(accessToken: token, albumID: albumID, limit: Self.pageSize, offset: offset)
            return (page.items, page.next, page.total)
        }

        let showEpisodes = await hydrateChildren(
            label: "saved show",
            containers: savedShows,
            containerID: { $0.show.id },
            containerName: { $0.show.name },
            max: Self.maxSavedShowEpisodesTotal,
            progress: progress
        ) { showID, offset in
            let page = try await api.fetchShowEpisodes(accessToken: token, showID: showID, limit: Self.pageSize, offset: offset)
            return (page.items, page.next, page.total)
        }

        let audiobookChapters = await hydrateChildren(
            label: "saved audiobook",
            containers: savedAudiobooks,
            containerID: { $0.id },
            containerName: { $0.name },
            max: Self.maxSavedAudiobookChaptersTotal,
            progress: progress
        ) { audiobookID, offset in
            let page = try await api.fetchAudiobookChapters(accessToken: token, audiobookID: audiobookID, limit: Self.pageSize, offset: offset)
            return (page.items, page.next, page.total)
        }

        return (albumTracks, showEpisodes, audiobookChapters)
    }

    private func hydrateChildren<Container, Item>(
        label: String,
        containers: [Container],
        containerID: (Container) -> String,
        containerName: (Container) -> String,
        max maxCount: Int,
        progress: @escaping (String?) -> Void,
        fetch: (_ id: String, _ offset: Int) async throws -> (items: [Item], next: String?, total: Int?)
    ) async -> [String: [Item]] {
        var itemsByID: [String: [Item]] = [:]
        var remaining = maxCount

        for (index, container) in containers.enumerated() {
            if Task.isCancelled || remaining <= 0 { break }
            let id = containerID(container)
            if shouldReport(index: index, total: containers.count) {
                progress("Reading \(label) \(index + 1)/\(containers.count): \(containerName(container))")
            }
            let items = (try? await allPages(max: remaining) { offset in
                try await fetch(id, offset)
            }) ?? []
            if !items.isEmpty {
                itemsByID[id] = items
                remaining -= items.count
            }
        }

        return itemsByID
    }

    private func allPages<Item>(
        max maxCount: Int,
        fetch: (_ offset: Int) async throws -> (items: [Item], next: String?, total: Int?)
    ) async throws -> [Item] {
        var all: [Item] = []
        var offset = 0
        while all.count < maxCount {
            try Task.checkCancellation()
            let page = try await fetch(offset)
            if page.items.isEmpty { break }
            all.append(contentsOf: page.items)
            offset += page.items.count
            if page.next == nil { break }
            if let total = page.total, offset >= total { break }
        }
        return Array(all.prefix(maxCount))
    }

    private func shouldReport(index: Int, total: Int) -> Bool {
        index == 0 || (index + 1).isMultiple(of: 25) || index == total - 1
    }
}

/// The Spotify music node — the first personality node.
///
/// It owns the full lifecycle for connecting a user's Spotify account and then
/// pulling the most complete possible picture of their listening identity into
/// memory: profile, playback, taste (top tracks + artists across every time
/// range), the entire saved library (tracks, albums, shows, episodes,
/// audiobooks), followed artists, and every playlist hydrated to its tracks.
///
/// Captured data stays on the device — nothing is sent anywhere. The full
/// snapshot is persisted locally (tokens in the keychain, data as JSON) so once
/// the node is connected it stays set up: on relaunch it shows the saved
/// snapshot instantly and never re-syncs unless the user asks.
@MainActor
@Observable
final class SpotifyMusicNode {
    // Depth caps. Generous, but bounded so a runaway library can't spin forever.
    private static let pageSize = 50
    private static let maxSavedTracks = 10_000
    private static let maxSavedAlbums = 2_000
    private static let maxSavedShows = 1_000
    private static let maxSavedEpisodes = 2_000
    private static let maxSavedAudiobooks = 1_000
    private static let maxSavedAlbumTracksTotal = 50_000
    private static let maxSavedShowEpisodesTotal = 50_000
    private static let maxSavedAudiobookChaptersTotal = 20_000
    private static let maxFollowedArtists = 2_000
    private static let maxPlaylists = 500
    private static let maxPlaylistTracksTotal = 50_000
    private static let topItemsPerRange = 50

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

    // The full in-memory snapshot.
    private(set) var profile: SpotifyUserProfile?
    private(set) var currentlyPlaying: SpotifyCurrentPlayback?
    private(set) var playbackState: SpotifyCurrentPlayback?
    private(set) var availableDevices: [SpotifyPlaybackDevice] = []
    private(set) var queue: SpotifyQueueResponse?
    private(set) var recentlyPlayed: [SpotifyRecentlyPlayedItem] = []
    private(set) var topTracksShort: [SpotifyTrack] = []
    private(set) var topTracksMedium: [SpotifyTrack] = []
    private(set) var topTracksLong: [SpotifyTrack] = []
    private(set) var topArtistsShort: [SpotifyArtist] = []
    private(set) var topArtistsMedium: [SpotifyArtist] = []
    private(set) var topArtistsLong: [SpotifyArtist] = []
    private(set) var savedTracks: [SpotifySavedTrack] = []
    private(set) var savedAlbums: [SpotifySavedAlbum] = []
    private(set) var savedShows: [SpotifySavedShow] = []
    private(set) var savedEpisodes: [SpotifySavedEpisode] = []
    private(set) var savedAudiobooks: [SpotifyAudiobook] = []
    private(set) var savedAlbumTracksByID: [String: [SpotifyTrack]] = [:]
    private(set) var savedShowEpisodesByID: [String: [SpotifyEpisode]] = [:]
    private(set) var savedAudiobookChaptersByID: [String: [SpotifyChapter]] = [:]
    private(set) var followedArtists: [SpotifyArtist] = []
    private(set) var playlists: [SpotifyPlaylist] = []
    private(set) var playlistItemsByID: [String: [SpotifyPlaylistItem]] = [:]

    // MARK: Private

    @ObservationIgnored private let config: SpotifyAppConfiguration
    @ObservationIgnored private let tokenStore = SpotifyTokenStore()
    @ObservationIgnored private let api = SpotifyWebAPI()
    @ObservationIgnored private let presentationContextProvider = SpotifyAuthPresentationContextProvider()
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var tokens: SpotifyAuthorizationTokens?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let syncWorker = SpotifySyncWorker()
    @ObservationIgnored private let snapshotStore = SnapshotStore<SpotifyNodeSnapshot>(filename: "spotify-snapshot.json")

    init(config: SpotifyAppConfiguration? = nil) {
        let resolved = config ?? SpotifyAppConfiguration.current(bundle: .main)
        self.config = resolved
        isConfigured = resolved.isConfigured
        configurationMessage = resolved.missingConfigurationReason
        loadCachedSnapshot()
        if loadStoredTokensIfAvailable() || hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    var statusSummary: String {
        if !isConfigured { return configurationMessage ?? "Spotify is not configured." }
        if isAuthorizing { return "Connecting to Spotify…" }
        if isSyncing { return syncProgress ?? "Pulling everything from Spotify…" }
        if isAuthorized, let profile { return "Connected as \(profile.resolvedDisplayName)" }
        if isAuthorized, hasRestoredSnapshot { return "Restored Spotify snapshot" }
        return "Spotify not connected."
    }

    var callbackURIString: String { config.redirectURI.absoluteString }

    /// Total number of tracks held across every playlist.
    var hydratedPlaylistTrackCount: Int {
        playlistItemsByID.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Lifecycle

    func restoreSessionIfPossible() async {
        isConfigured = config.isConfigured
        configurationMessage = config.missingConfigurationReason
        guard isConfigured else { return }

        loadCachedSnapshot()

        if loadStoredTokensIfAvailable() {
            isAuthorized = true
            // Only auto-sync the first time. Once a snapshot exists the node
            // stays set up and shows saved data instantly; refreshing is a
            // manual choice via the refresh button.
            if !hasRestoredSnapshot {
                await syncEverything()
            }
        } else if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    private func loadCachedSnapshot() {
        guard let snapshot = snapshotStore.load() else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: SpotifyNodeSnapshot) {
        profile = snapshot.profile
        currentlyPlaying = snapshot.currentlyPlaying
        playbackState = snapshot.playbackState
        availableDevices = snapshot.availableDevices
        queue = snapshot.queue
        recentlyPlayed = snapshot.recentlyPlayed
        topTracksShort = snapshot.topTracksShort
        topTracksMedium = snapshot.topTracksMedium
        topTracksLong = snapshot.topTracksLong
        topArtistsShort = snapshot.topArtistsShort
        topArtistsMedium = snapshot.topArtistsMedium
        topArtistsLong = snapshot.topArtistsLong
        savedTracks = snapshot.savedTracks
        savedAlbums = snapshot.savedAlbums
        savedShows = snapshot.savedShows
        savedEpisodes = snapshot.savedEpisodes
        savedAudiobooks = snapshot.savedAudiobooks
        savedAlbumTracksByID = snapshot.savedAlbumTracksByID
        savedShowEpisodesByID = snapshot.savedShowEpisodesByID
        savedAudiobookChaptersByID = snapshot.savedAudiobookChaptersByID
        followedArtists = snapshot.followedArtists
        playlists = snapshot.playlists
        playlistItemsByID = snapshot.playlistItemsByID
        grantedScopes = snapshot.grantedScopes
        lastSyncedAt = snapshot.lastSyncedAt
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    private func saveCachedSnapshot() {
        snapshotStore.save(
            SpotifyNodeSnapshot(
                profile: profile,
                currentlyPlaying: currentlyPlaying,
                playbackState: playbackState,
                availableDevices: availableDevices,
                queue: queue,
                recentlyPlayed: recentlyPlayed,
                topTracksShort: topTracksShort,
                topTracksMedium: topTracksMedium,
                topTracksLong: topTracksLong,
                topArtistsShort: topArtistsShort,
                topArtistsMedium: topArtistsMedium,
                topArtistsLong: topArtistsLong,
                savedTracks: savedTracks,
                savedAlbums: savedAlbums,
                savedShows: savedShows,
                savedEpisodes: savedEpisodes,
                savedAudiobooks: savedAudiobooks,
                savedAlbumTracksByID: savedAlbumTracksByID,
                savedShowEpisodesByID: savedShowEpisodesByID,
                savedAudiobookChaptersByID: savedAudiobookChaptersByID,
                followedArtists: followedArtists,
                playlists: playlists,
                playlistItemsByID: playlistItemsByID,
                grantedScopes: grantedScopes,
                lastSyncedAt: lastSyncedAt
            )
        )
    }

    func connect() async {
        lastErrorMessage = nil
        guard isConfigured else {
            lastErrorMessage = configurationMessage ?? "Spotify is not configured."
            return
        }

        // Already connected, or a saved token sitting in the keychain — reuse it.
        // Re-running OAuth on every connect hammers Spotify's authorize endpoint
        // and gets the client throttled (it answers with a generic server_error).
        // Connect once, set up forever: only authorize fresh when we have nothing.
        if isAuthorized || loadStoredTokensIfAvailable() {
            isAuthorized = true
            if !hasRestoredSnapshot {
                await syncEverything()
            }
            return
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
            await syncEverything()
        } catch {
            isAuthorizing = false
            if (error as NSError).domain == ASWebAuthenticationSessionError.errorDomain,
               (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                lastErrorMessage = "Spotify authorization cancelled."
            } else {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// Pull a previously saved token into memory if we don't already have one,
    /// so `connect()` can resume the session without a fresh authorize.
    private func loadStoredTokensIfAvailable() -> Bool {
        if tokens != nil { return true }
        if let stored = (try? tokenStore.load()) ?? nil {
            tokens = stored
            grantedScopes = stored.scopes.sorted()
            return true
        }
        return false
    }

    private var hasRestoredSnapshot: Bool {
        profile != nil ||
            lastSyncedAt != nil ||
            !topTracksShort.isEmpty ||
            !topArtistsShort.isEmpty ||
            !savedTracks.isEmpty ||
            !playlists.isEmpty
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
        profile = nil
        currentlyPlaying = nil
        playbackState = nil
        availableDevices = []
        queue = nil
        recentlyPlayed = []
        topTracksShort = []
        topTracksMedium = []
        topTracksLong = []
        topArtistsShort = []
        topArtistsMedium = []
        topArtistsLong = []
        savedTracks = []
        savedAlbums = []
        savedShows = []
        savedEpisodes = []
        savedAudiobooks = []
        savedAlbumTracksByID = [:]
        savedShowEpisodesByID = [:]
        savedAudiobookChaptersByID = [:]
        followedArtists = []
        playlists = []
        playlistItemsByID = [:]
        lastSyncedAt = nil
        snapshotStore.delete()
    }

    /// Re-pull everything. Coalesces concurrent callers onto a single task.
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
            } catch SpotifyAPIError.unauthorized {
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

    func verifyCatalogRecommendation(_ recommendation: BrainMusicRecommendation) async -> BrainCatalogVerification {
        guard isConfigured else {
            return .unavailable("Spotify", message: "Spotify is not configured for catalog verification.")
        }

        do {
            let token = try await validAccessToken()
            let query = "track:\"\(recommendation.title)\" artist:\"\(recommendation.artist)\""
            let response = try await api.searchTracks(accessToken: token, query: query, limit: 10)
            let candidates = response.tracks.items.map { track in
                BrainCatalogCandidate(
                    source: "Spotify",
                    title: track.name,
                    artist: track.primaryArtist,
                    album: track.album?.name,
                    url: track.spotifyURL?.absoluteString
                )
            }
            return BrainCatalogMatcher.verify(recommendation, candidates: candidates, source: "Spotify")
        } catch SpotifyAPIError.unauthorized {
            return .unavailable("Spotify", message: "Spotify token is unavailable for catalog verification.")
        } catch {
            return .unavailable("Spotify", message: "Spotify catalog verification failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Full sync

    private func runFullSync() async throws {
        let token = try await validAccessToken()
        lastErrorMessage = nil

        report("Preparing Spotify sync…")
        let scopes = grantedScopes
        let snapshot = try await syncWorker.sync(accessToken: token, grantedScopes: scopes) { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncing else { return }
                self.report(message)
            }
        }
        apply(snapshot)
        saveCachedSnapshot()
        report(nil)
    }

    private func dedupedRecentlyPlayed(token: String) async throws -> [SpotifyRecentlyPlayedItem] {
        let response = try await api.fetchRecentlyPlayed(accessToken: token, limit: Self.pageSize)
        var seen = Set<String>()
        return response.items.filter { seen.insert($0.id).inserted }
    }

    private func allTopTracks(token: String, range: String) async throws -> [SpotifyTrack] {
        try await allPages(max: Self.topItemsPerRange) { offset in
            let page = try await api.fetchTopTracks(accessToken: token, limit: Self.pageSize, offset: offset, timeRange: range)
            return (page.items, page.next, page.total)
        }
    }

    private func allTopArtists(token: String, range: String) async throws -> [SpotifyArtist] {
        try await allPages(max: Self.topItemsPerRange) { offset in
            let page = try await api.fetchTopArtists(accessToken: token, limit: Self.pageSize, offset: offset, timeRange: range)
            return (page.items, page.next, page.total)
        }
    }

    private func allFollowedArtists(token: String) async throws -> [SpotifyArtist] {
        var all: [SpotifyArtist] = []
        var after: String?
        repeat {
            let response = try await api.fetchFollowedArtists(accessToken: token, after: after, limit: Self.pageSize)
            all.append(contentsOf: response.artists.items)
            after = response.artists.cursors?.after
            if response.artists.next == nil || after == nil { break }
        } while all.count < Self.maxFollowedArtists
        return Array(all.prefix(Self.maxFollowedArtists))
    }

    private func hydratePlaylists(token: String) async throws {
        var itemsByID: [String: [SpotifyPlaylistItem]] = [:]
        var remaining = Self.maxPlaylistTracksTotal

        for (index, playlist) in playlists.enumerated() {
            guard remaining > 0 else { break }
            report("Reading playlist \(index + 1)/\(playlists.count): \(playlist.name)")
            let items = try await allPages(max: remaining) { offset in
                let page = try await api.fetchPlaylistItems(
                    accessToken: token,
                    playlistID: playlist.id,
                    limit: Self.pageSize,
                    offset: offset
                )
                return (page.items, page.next, page.total)
            }
            itemsByID[playlist.id] = items
            remaining -= items.count
        }
        playlistItemsByID = itemsByID
    }

    private func hydrateSavedLibraryChildren(token: String) async {
        savedAlbumTracksByID = await hydrateChildren(
            label: "saved album",
            containers: savedAlbums,
            containerID: { $0.album.id },
            containerName: { $0.album.name },
            max: Self.maxSavedAlbumTracksTotal
        ) { albumID, offset in
            let page = try await api.fetchAlbumTracks(accessToken: token, albumID: albumID, limit: Self.pageSize, offset: offset)
            return (page.items, page.next, page.total)
        }

        savedShowEpisodesByID = await hydrateChildren(
            label: "saved show",
            containers: savedShows,
            containerID: { $0.show.id },
            containerName: { $0.show.name },
            max: Self.maxSavedShowEpisodesTotal
        ) { showID, offset in
            let page = try await api.fetchShowEpisodes(accessToken: token, showID: showID, limit: Self.pageSize, offset: offset)
            return (page.items, page.next, page.total)
        }

        savedAudiobookChaptersByID = await hydrateChildren(
            label: "saved audiobook",
            containers: savedAudiobooks,
            containerID: { $0.id },
            containerName: { $0.name },
            max: Self.maxSavedAudiobookChaptersTotal
        ) { audiobookID, offset in
            let page = try await api.fetchAudiobookChapters(accessToken: token, audiobookID: audiobookID, limit: Self.pageSize, offset: offset)
            return (page.items, page.next, page.total)
        }
    }

    private func hydrateChildren<Container, Item>(
        label: String,
        containers: [Container],
        containerID: (Container) -> String,
        containerName: (Container) -> String,
        max maxCount: Int,
        fetch: (_ id: String, _ offset: Int) async throws -> (items: [Item], next: String?, total: Int?)
    ) async -> [String: [Item]] {
        var itemsByID: [String: [Item]] = [:]
        var remaining = maxCount

        for (index, container) in containers.enumerated() {
            guard remaining > 0 else { break }
            let id = containerID(container)
            report("Reading \(label) \(index + 1)/\(containers.count): \(containerName(container))")
            let items = (try? await allPages(max: remaining) { offset in
                try await fetch(id, offset)
            }) ?? []
            if !items.isEmpty {
                itemsByID[id] = items
                remaining -= items.count
            }
        }

        return itemsByID
    }

    /// Generic offset-based pagination loop. `fetch` returns one page plus the
    /// `next` link and `total`; we keep going until exhausted or `max` is hit.
    private func allPages<Item>(
        max maxCount: Int,
        fetch: (_ offset: Int) async throws -> (items: [Item], next: String?, total: Int?)
    ) async throws -> [Item] {
        var all: [Item] = []
        var offset = 0
        while all.count < maxCount {
            let page = try await fetch(offset)
            if page.items.isEmpty { break }
            all.append(contentsOf: page.items)
            offset += page.items.count
            if page.next == nil { break }
            if let total = page.total, offset >= total { break }
        }
        return Array(all.prefix(maxCount))
    }

    private func report(_ message: String?) {
        syncProgress = message
    }

    // MARK: - Tokens

    private func validAccessToken() async throws -> String {
        guard let tokens else { throw SpotifyAPIError.unauthorized }
        if tokens.needsRefresh {
            return try await refreshTokens().accessToken
        }
        return tokens.accessToken
    }

    @discardableResult
    private func refreshTokens() async throws -> SpotifyAuthorizationTokens {
        guard let tokens else { throw SpotifyAPIError.unauthorized }
        guard !tokens.refreshToken.isEmpty else { throw SpotifyAPIError.missingRefreshToken }

        let response = try await api.refreshTokens(config: config, refreshToken: tokens.refreshToken)
        let refreshed = tokens.refreshed(with: response)
        try tokenStore.save(refreshed)
        self.tokens = refreshed
        grantedScopes = refreshed.scopes.sorted()
        isAuthorized = true
        return refreshed
    }

    // MARK: - PKCE authorization

    /// Runs the PKCE flow and exchanges the code for tokens. Spotify's authorize
    /// endpoint intermittently returns `server_error` (especially on rapid
    /// re-consent), so a single transient failure is retried once.
    private func acquireTokens() async throws -> SpotifyAuthorizationTokens {
        func once() async throws -> SpotifyAuthorizationTokens {
            let result = try await authorizeWithPKCE()
            let tokenResponse = try await api.exchangeAuthorizationCode(
                config: config,
                code: result.authorizationCode,
                codeVerifier: result.codeVerifier
            )
            let tokens = SpotifyAuthorizationTokens(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken ?? "",
                tokenType: tokenResponse.tokenType,
                scopes: tokenResponse.scopeList.isEmpty ? SpotifyAppConfiguration.requiredScopes : tokenResponse.scopeList,
                expirationDate: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            )
            guard !tokens.refreshToken.isEmpty else { throw SpotifyAPIError.missingRefreshToken }
            return tokens
        }

        do {
            return try await once()
        } catch {
            // Transient Spotify-side error — one retry.
            if case let SpotifyAPIError.http(status, message) = error, status == 400,
               let message, message.contains("server_error") || message.contains("temporarily_unavailable") {
                return try await once()
            }
            throw error
        }
    }

    private func authorizeWithPKCE() async throws -> SpotifyAuthorizationResult {
        let codeVerifier = Self.randomURLSafeString(length: 96)
        let state = Self.randomURLSafeString(length: 32)
        let codeChallenge = Self.codeChallenge(for: codeVerifier)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: SpotifyAppConfiguration.requiredScopes.joined(separator: " ")),
            // Don't force the consent dialog every time — a fresh user still sees
            // it (no prior grant), but re-auth reuses the existing session. Forcing
            // it on rapid re-consent is a common trigger for Spotify's server_error.
            URLQueryItem(name: "show_dialog", value: "false"),
        ]

        guard let url = components.url, let callbackScheme = config.callbackScheme else {
            throw SpotifyConfigError.invalidRedirectURI(config.redirectURI.absoluteString)
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
                    continuation.resume(throwing: SpotifyAPIError.invalidResponse)
                }
            }
            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuation.resume(throwing: SpotifyAPIError.invalidResponse)
            }
        }

        authSession = nil

        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let items = components.queryItems
        else {
            throw SpotifyAPIError.invalidResponse
        }

        let returnedState = items.first(where: { $0.name == "state" })?.value
        let code = items.first(where: { $0.name == "code" })?.value
        let authError = items.first(where: { $0.name == "error" })?.value

        if let authError {
            throw SpotifyAPIError.http(statusCode: 400, message: authError)
        }
        guard returnedState == state, let code, !code.isEmpty else {
            throw SpotifyAPIError.invalidResponse
        }

        return SpotifyAuthorizationResult(authorizationCode: code, codeVerifier: codeVerifier)
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

private struct SpotifyAuthorizationResult {
    let authorizationCode: String
    let codeVerifier: String
}

private final class SpotifyAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
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
