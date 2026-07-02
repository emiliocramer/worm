import Foundation
import MediaPlayer
import MusicKit
import Observation

// MARK: - Lightweight in-memory models

struct AMArtwork: Hashable, Codable {
    let url: String?
    let maximumWidth: Int
    let maximumHeight: Int
    let alternateText: String?
}

struct AMEditorialNotes: Hashable, Codable {
    let short: String?
    let standard: String?
    let name: String?
    let tagline: String?
}

struct AMPreviewAsset: Hashable, Codable {
    let url: String?
    let hlsURL: String?
    let artwork: AMArtwork?
}

struct AMTrack: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let artistURL: String?
    let attribution: String?
    let composer: String?
    let contentRating: String?
    let discNumber: Int?
    let duration: TimeInterval?
    let editorialNotes: AMEditorialNotes?
    let genreNames: [String]
    let hasLyrics: Bool
    let audioVariants: [String]
    let isAppleDigitalMaster: Bool?
    let isrc: String?
    let lastPlayedDate: Date?
    let libraryAddedDate: Date?
    let playCount: Int?
    let movementCount: Int?
    let movementName: String?
    let movementNumber: Int?
    let previewAssets: [AMPreviewAsset]
    let releaseDate: Date?
    let trackNumber: Int?
    let url: String?
    let workName: String?
    let artwork: AMArtwork?
}

struct AMAlbum: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String
    let artistURL: String?
    let contentRating: String?
    let copyright: String?
    let editorialNotes: AMEditorialNotes?
    let genreNames: [String]
    let audioVariants: [String]
    let isAppleDigitalMaster: Bool?
    let isCompilation: Bool?
    let isComplete: Bool?
    let isSingle: Bool?
    let lastPlayedDate: Date?
    let libraryAddedDate: Date?
    let recordLabel: String?
    let releaseDate: Date?
    let trackCount: Int
    let upc: String?
    let url: String?
    let artwork: AMArtwork?
}

struct AMAlbumTrack: Identifiable, Hashable, Codable {
    let id: String
    let albumID: String
    let position: Int
    let itemKind: String
    let title: String
    let artist: String
    let albumTitle: String?
    let artistURL: String?
    let contentRating: String?
    let discNumber: Int?
    let duration: TimeInterval?
    let editorialNotes: AMEditorialNotes?
    let genreNames: [String]
    let lastPlayedDate: Date?
    let libraryAddedDate: Date?
    let playCount: Int?
    let isrc: String?
    let playParametersDescription: String?
    let previewAssets: [AMPreviewAsset]
    let releaseDate: Date?
    let trackNumber: Int?
    let url: String?
    let workName: String?
    let artwork: AMArtwork?
    let musicVideoHas4K: Bool?
    let musicVideoHasHDR: Bool?
    let musicVideoIsPreview: Bool?
    let musicVideoStartTime: TimeInterval?
    let musicVideoEndTime: TimeInterval?
}

struct AMArtist: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let genreNames: [String]
    let libraryAddedDate: Date?
    let url: String?
    let artwork: AMArtwork?
    let editorialNotes: AMEditorialNotes?
}

struct AMPlaylist: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let curator: String?
    let isChart: Bool?
    let kind: String?
    let lastModifiedDate: Date?
    let lastPlayedDate: Date?
    let libraryAddedDate: Date?
    let shortDescription: String?
    let standardDescription: String?
    let url: String?
    let artwork: AMArtwork?
}

struct AMPlaylistEntry: Identifiable, Hashable, Codable {
    let id: String
    let itemID: String?
    let playlistID: String
    let position: Int
    let itemKind: String
    let title: String
    let artist: String
    let albumTitle: String?
    let artistURL: String?
    let contentRating: String?
    let duration: TimeInterval?
    let editorialNotes: AMEditorialNotes?
    let genreNames: [String]
    let lastPlayedDate: Date?
    let libraryAddedDate: Date?
    let playCount: Int?
    let isrc: String?
    let playParametersDescription: String?
    let previewAssets: [AMPreviewAsset]
    let releaseDate: Date?
    let url: String?
    let artwork: AMArtwork?
    let musicVideoHas4K: Bool?
    let musicVideoHasHDR: Bool?
    let musicVideoIsPreview: Bool?
    let musicVideoTrackNumber: Int?
    let musicVideoWorkName: String?
    let musicVideoStartTime: TimeInterval?
    let musicVideoEndTime: TimeInterval?
}

struct AMRecommendation: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let itemCount: Int
}

/// The full in-memory state of the Apple Music node, persisted to disk so a
/// returning user sees their data instantly instead of re-syncing everything.
struct AppleMusicNodeSnapshot: Codable {
    let canPlayCatalogContent: Bool
    let canBecomeSubscriber: Bool
    let songs: [AMTrack]
    let albums: [AMAlbum]
    let albumTracksByID: [String: [AMAlbumTrack]]
    let artists: [AMArtist]
    let playlists: [AMPlaylist]
    let playlistEntriesByID: [String: [AMPlaylistEntry]]
    let recentlyPlayed: [AMTrack]
    let recommendations: [AMRecommendation]
    let nowPlayingTitle: String?
    let nowPlayingArtist: String?
    let lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case canPlayCatalogContent
        case canBecomeSubscriber
        case songs
        case albums
        case albumTracksByID
        case artists
        case playlists
        case playlistEntriesByID
        case recentlyPlayed
        case recommendations
        case nowPlayingTitle
        case nowPlayingArtist
        case lastSyncedAt
    }

    init(
        canPlayCatalogContent: Bool,
        canBecomeSubscriber: Bool,
        songs: [AMTrack],
        albums: [AMAlbum],
        albumTracksByID: [String: [AMAlbumTrack]],
        artists: [AMArtist],
        playlists: [AMPlaylist],
        playlistEntriesByID: [String: [AMPlaylistEntry]],
        recentlyPlayed: [AMTrack],
        recommendations: [AMRecommendation],
        nowPlayingTitle: String?,
        nowPlayingArtist: String?,
        lastSyncedAt: Date?
    ) {
        self.canPlayCatalogContent = canPlayCatalogContent
        self.canBecomeSubscriber = canBecomeSubscriber
        self.songs = songs
        self.albums = albums
        self.albumTracksByID = albumTracksByID
        self.artists = artists
        self.playlists = playlists
        self.playlistEntriesByID = playlistEntriesByID
        self.recentlyPlayed = recentlyPlayed
        self.recommendations = recommendations
        self.nowPlayingTitle = nowPlayingTitle
        self.nowPlayingArtist = nowPlayingArtist
        self.lastSyncedAt = lastSyncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canPlayCatalogContent = try container.decode(Bool.self, forKey: .canPlayCatalogContent)
        canBecomeSubscriber = try container.decode(Bool.self, forKey: .canBecomeSubscriber)
        songs = try container.decode([AMTrack].self, forKey: .songs)
        albums = try container.decode([AMAlbum].self, forKey: .albums)
        albumTracksByID = try container.decodeIfPresent([String: [AMAlbumTrack]].self, forKey: .albumTracksByID) ?? [:]
        artists = try container.decode([AMArtist].self, forKey: .artists)
        playlists = try container.decode([AMPlaylist].self, forKey: .playlists)
        playlistEntriesByID = try container.decodeIfPresent([String: [AMPlaylistEntry]].self, forKey: .playlistEntriesByID) ?? [:]
        recentlyPlayed = try container.decode([AMTrack].self, forKey: .recentlyPlayed)
        recommendations = try container.decode([AMRecommendation].self, forKey: .recommendations)
        nowPlayingTitle = try container.decodeIfPresent(String.self, forKey: .nowPlayingTitle)
        nowPlayingArtist = try container.decodeIfPresent(String.self, forKey: .nowPlayingArtist)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
    }
}

private actor AppleMusicSyncWorker {
    private static let pageSize = 100
    private static let maxSongs = 25_000
    private static let maxAlbums = 5_000
    private static let maxAlbumTracks = 50_000
    private static let maxArtists = 5_000
    private static let maxPlaylists = 1_000
    private static let maxPlaylistEntries = 50_000

    func sync(progress: @escaping (String?) -> Void) async throws -> AppleMusicNodeSnapshot {
        progress("Reading subscription…")
        var canPlayCatalogContent = false
        var canBecomeSubscriber = false
        if let subscription = try? await MusicSubscription.current {
            canPlayCatalogContent = subscription.canPlayCatalogContent
            canBecomeSubscriber = subscription.canBecomeSubscriber
        }

        progress("Reading library songs…")
        let songs = (try? await loadLibrary(Song.self, max: Self.maxSongs).map {
            AppleMusicNode.makeTrack($0)
        }) ?? []

        progress("Reading library albums…")
        let libraryAlbums = (try? await loadLibrary(Album.self, max: Self.maxAlbums)) ?? []
        let albums = libraryAlbums.map {
            AppleMusicNode.makeAlbum($0)
        }

        progress("Reading album tracks…")
        let albumTracksByID = await loadAlbumTracks(for: libraryAlbums, max: Self.maxAlbumTracks, progress: progress)

        progress("Reading library artists…")
        let artists = (try? await loadLibrary(Artist.self, max: Self.maxArtists).map {
            AppleMusicNode.makeArtist($0)
        }) ?? []

        progress("Reading library playlists…")
        let libraryPlaylists = (try? await loadLibrary(Playlist.self, max: Self.maxPlaylists)) ?? []
        let playlists = libraryPlaylists.map {
            AppleMusicNode.makePlaylist($0)
        }

        progress("Reading playlist entries…")
        let playlistEntriesByID = await loadPlaylistEntries(for: libraryPlaylists, max: Self.maxPlaylistEntries, progress: progress)

        progress("Reading recently played…")
        let recentlyPlayed: [AMTrack]
        if let response = try? await MusicRecentlyPlayedRequest<Song>().response() {
            recentlyPlayed = response.items.map {
                AppleMusicNode.makeTrack($0)
            }
        } else {
            recentlyPlayed = []
        }

        progress("Reading recommendations…")
        let recommendations: [AMRecommendation]
        if let response = try? await MusicPersonalRecommendationsRequest().response() {
            recommendations = response.recommendations.map { recommendation in
                AMRecommendation(
                    id: recommendation.id.rawValue,
                    title: recommendation.title ?? "Recommendation",
                    itemCount: recommendation.items.count
                )
            }
        } else {
            recommendations = []
        }

        return AppleMusicNodeSnapshot(
            canPlayCatalogContent: canPlayCatalogContent,
            canBecomeSubscriber: canBecomeSubscriber,
            songs: songs,
            albums: albums,
            albumTracksByID: albumTracksByID,
            artists: artists,
            playlists: playlists,
            playlistEntriesByID: playlistEntriesByID,
            recentlyPlayed: recentlyPlayed,
            recommendations: recommendations,
            nowPlayingTitle: nil,
            nowPlayingArtist: nil,
            lastSyncedAt: Date()
        )
    }

    private func loadLibrary<T: MusicLibraryRequestable>(_ type: T.Type, max maxCount: Int) async throws -> [T] {
        var request = MusicLibraryRequest<T>()
        request.limit = Self.pageSize
        var collection = try await request.response().items
        var all: [T] = Array(collection)
        while collection.hasNextBatch, all.count < maxCount {
            try Task.checkCancellation()
            guard let next = try await collection.nextBatch() else { break }
            collection = next
            all.append(contentsOf: next)
        }
        return Array(all.prefix(maxCount))
    }

    private func loadPlaylistEntries(
        for playlists: [Playlist],
        max maxCount: Int,
        progress: @escaping (String?) -> Void
    ) async -> [String: [AMPlaylistEntry]] {
        guard maxCount > 0 else { return [:] }

        var remaining = maxCount
        var entriesByID: [String: [AMPlaylistEntry]] = [:]
        for (index, playlist) in playlists.enumerated() {
            if Task.isCancelled || remaining <= 0 { break }
            if shouldReport(index: index, total: playlists.count) {
                progress("Reading playlist \(index + 1) of \(playlists.count)…")
            }

            guard let hydrated = try? await playlist.with(.entries), let entries = hydrated.entries else {
                continue
            }

            let allEntries = await loadAll(entries, max: remaining)
            let mapped = allEntries.map {
                AppleMusicNode.makePlaylistEntry($0, playlistID: playlist.id.rawValue)
            }
            if !mapped.isEmpty {
                entriesByID[playlist.id.rawValue] = mapped
                remaining -= mapped.count
            }
        }
        return entriesByID
    }

    private func loadAlbumTracks(
        for albums: [Album],
        max maxCount: Int,
        progress: @escaping (String?) -> Void
    ) async -> [String: [AMAlbumTrack]] {
        guard maxCount > 0 else { return [:] }

        var remaining = maxCount
        var tracksByID: [String: [AMAlbumTrack]] = [:]
        for (index, album) in albums.enumerated() {
            if Task.isCancelled || remaining <= 0 { break }
            if shouldReport(index: index, total: albums.count) {
                progress("Reading album \(index + 1) of \(albums.count)…")
            }

            guard let hydrated = try? await album.with(.tracks), let tracks = hydrated.tracks else {
                continue
            }

            let allTracks = await loadAll(tracks, max: remaining)
            let mapped = allTracks.enumerated().map { position, track in
                AppleMusicNode.makeAlbumTrack(track, albumID: album.id.rawValue, position: position)
            }
            if !mapped.isEmpty {
                tracksByID[album.id.rawValue] = mapped
                remaining -= mapped.count
            }
        }
        return tracksByID
    }

    private func loadAll<T: MusicItem & Decodable>(_ collection: MusicItemCollection<T>, max maxCount: Int) async -> [T] {
        var page = collection
        var all: [T] = Array(page.prefix(maxCount))
        while page.hasNextBatch, all.count < maxCount {
            if Task.isCancelled { break }
            let nextLimit = min(Self.pageSize, maxCount - all.count)
            guard let next = try? await page.nextBatch(limit: nextLimit) else { break }
            page = next
            all.append(contentsOf: next.prefix(maxCount - all.count))
        }
        return all
    }

    private func shouldReport(index: Int, total: Int) -> Bool {
        index == 0 || (index + 1).isMultiple(of: 25) || index == total - 1
    }
}

/// The Apple Music node — the second personality node.
///
/// Same shape as the Spotify node, but built on MusicKit instead of OAuth. After
/// the user authorizes, it pulls the most complete possible picture of their
/// Apple Music identity into memory: subscription state, the entire library
/// (songs, albums, artists, playlists), recently played, personal
/// recommendations, and the current now-playing item.
///
/// Captured data stays on the device — nothing is sent anywhere. The full
/// snapshot is persisted locally as JSON so once the node is connected it stays
/// set up: on relaunch it shows the saved snapshot instantly and never re-syncs
/// unless the user asks.
@MainActor
@Observable
final class AppleMusicNode {
    private static let pageSize = 100
    private static let maxSongs = 25_000
    private static let maxAlbums = 5_000
    private static let maxAlbumTracks = 50_000
    private static let maxArtists = 5_000
    private static let maxPlaylists = 1_000
    private static let maxPlaylistEntries = 50_000

    // MARK: Observable state

    private(set) var isAuthorized = false
    private(set) var isAuthorizing = false
    private(set) var isSyncing = false
    private(set) var authorizationStatusText = "Not requested"
    private(set) var syncProgress: String?
    private(set) var lastSyncedAt: Date?
    private(set) var lastErrorMessage: String?

    // Subscription
    private(set) var canPlayCatalogContent = false
    private(set) var canBecomeSubscriber = false

    // The full in-memory snapshot.
    private(set) var songs: [AMTrack] = []
    private(set) var albums: [AMAlbum] = []
    private(set) var albumTracksByID: [String: [AMAlbumTrack]] = [:]
    private(set) var artists: [AMArtist] = []
    private(set) var playlists: [AMPlaylist] = []
    private(set) var playlistEntriesByID: [String: [AMPlaylistEntry]] = [:]
    private(set) var recentlyPlayed: [AMTrack] = []
    private(set) var recommendations: [AMRecommendation] = []
    private(set) var nowPlayingTitle: String?
    private(set) var nowPlayingArtist: String?

    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let syncWorker = AppleMusicSyncWorker()
    @ObservationIgnored private let snapshotStore = SnapshotStore<AppleMusicNodeSnapshot>(filename: "apple-music-snapshot.json")

    init() {
        loadCachedSnapshot()
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    var statusSummary: String {
        if isAuthorizing { return "Requesting Apple Music access…" }
        if isSyncing { return syncProgress ?? "Pulling everything from Apple Music…" }
        if isAuthorized { return "Connected to Apple Music" }
        return "Apple Music not connected."
    }

    // MARK: - Lifecycle

    func restoreSessionIfPossible() async {
        // Show the last synced snapshot immediately so a returning user sees
        // their data without waiting for a re-sync.
        loadCachedSnapshot()
        updateAuthStatusText(MusicAuthorization.currentStatus)
        if MusicAuthorization.currentStatus == .authorized {
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

    private func apply(_ snapshot: AppleMusicNodeSnapshot) {
        canPlayCatalogContent = snapshot.canPlayCatalogContent
        canBecomeSubscriber = snapshot.canBecomeSubscriber
        songs = snapshot.songs
        albums = snapshot.albums
        albumTracksByID = snapshot.albumTracksByID
        artists = snapshot.artists
        playlists = snapshot.playlists
        playlistEntriesByID = snapshot.playlistEntriesByID
        recentlyPlayed = snapshot.recentlyPlayed
        recommendations = snapshot.recommendations
        nowPlayingTitle = snapshot.nowPlayingTitle
        nowPlayingArtist = snapshot.nowPlayingArtist
        lastSyncedAt = snapshot.lastSyncedAt
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    private var hasRestoredSnapshot: Bool {
        lastSyncedAt != nil ||
            !songs.isEmpty ||
            !albums.isEmpty ||
            !artists.isEmpty ||
            !playlists.isEmpty ||
            !recentlyPlayed.isEmpty ||
            !recommendations.isEmpty
    }

    private func saveCachedSnapshot() {
        snapshotStore.save(
            AppleMusicNodeSnapshot(
                canPlayCatalogContent: canPlayCatalogContent,
                canBecomeSubscriber: canBecomeSubscriber,
                songs: songs,
                albums: albums,
                albumTracksByID: albumTracksByID,
                artists: artists,
                playlists: playlists,
                playlistEntriesByID: playlistEntriesByID,
                recentlyPlayed: recentlyPlayed,
                recommendations: recommendations,
                nowPlayingTitle: nowPlayingTitle,
                nowPlayingArtist: nowPlayingArtist,
                lastSyncedAt: lastSyncedAt
            )
        )
    }

    func connect() async {
        lastErrorMessage = nil
        isAuthorizing = true
        let status = await MusicAuthorization.request()
        updateAuthStatusText(status)
        isAuthorizing = false

        switch status {
        case .authorized:
            isAuthorized = true
            await syncEverything()
        case .denied:
            lastErrorMessage = "Apple Music access was denied. Enable it in Settings › Privacy › Media & Apple Music."
        case .restricted:
            lastErrorMessage = "Apple Music access is restricted on this device."
        case .notDetermined:
            lastErrorMessage = "Apple Music access was not determined."
        @unknown default:
            lastErrorMessage = "Unknown Apple Music authorization status."
        }
    }

    /// MusicKit authorization can only be revoked from iOS Settings, so this
    /// clears the in-memory snapshot and resets connection state.
    func disconnect() {
        syncTask?.cancel()
        syncTask = nil
        isAuthorized = false
        isSyncing = false
        syncProgress = nil
        canPlayCatalogContent = false
        canBecomeSubscriber = false
        songs = []
        albums = []
        albumTracksByID = [:]
        artists = []
        playlists = []
        playlistEntriesByID = [:]
        recentlyPlayed = []
        recommendations = []
        nowPlayingTitle = nil
        nowPlayingArtist = nil
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
        guard MusicAuthorization.currentStatus == .authorized else {
            return .unavailable("Apple Music", message: "Apple Music is not authorized for catalog verification.")
        }

        do {
            var request = MusicCatalogSearchRequest(
                term: "\(recommendation.title) \(recommendation.artist)",
                types: [Song.self]
            )
            request.limit = 10
            let response = try await request.response()
            let candidates = response.songs.map { song in
                BrainCatalogCandidate(
                    source: "Apple Music",
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle,
                    url: song.url?.absoluteString
                )
            }
            return BrainCatalogMatcher.verify(recommendation, candidates: Array(candidates), source: "Apple Music")
        } catch {
            return .unavailable("Apple Music", message: "Apple Music catalog verification failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Full sync

    private func runFullSync() async throws {
        lastErrorMessage = nil

        report("Preparing Apple Music sync…")
        let snapshot = try await syncWorker.sync { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncing else { return }
                self.report(message)
            }
        }
        apply(snapshot)
        report("Reading now playing…")
        readNowPlaying()

        saveCachedSnapshot()
        report(nil)
    }

    /// Generic offset-batched library pagination.
    private func loadLibrary<T: MusicLibraryRequestable>(_ type: T.Type, max maxCount: Int) async throws -> [T] {
        var request = MusicLibraryRequest<T>()
        request.limit = Self.pageSize
        var collection = try await request.response().items
        var all: [T] = Array(collection)
        while collection.hasNextBatch, all.count < maxCount {
            guard let next = try await collection.nextBatch() else { break }
            collection = next
            all.append(contentsOf: next)
        }
        return Array(all.prefix(maxCount))
    }

    private func loadPlaylistEntries(for playlists: [Playlist], max maxCount: Int) async -> [String: [AMPlaylistEntry]] {
        guard maxCount > 0 else { return [:] }

        var remaining = maxCount
        var entriesByID: [String: [AMPlaylistEntry]] = [:]
        for (index, playlist) in playlists.enumerated() {
            if Task.isCancelled || remaining <= 0 { break }
            report("Reading playlist \(index + 1) of \(playlists.count)…")

            guard let hydrated = try? await playlist.with(.entries), let entries = hydrated.entries else {
                continue
            }

            let allEntries = await loadAll(entries, max: remaining)
            let mapped = allEntries.map {
                Self.makePlaylistEntry($0, playlistID: playlist.id.rawValue)
            }
            if !mapped.isEmpty {
                entriesByID[playlist.id.rawValue] = mapped
                remaining -= mapped.count
            }
        }
        return entriesByID
    }

    private func loadAlbumTracks(for albums: [Album], max maxCount: Int) async -> [String: [AMAlbumTrack]] {
        guard maxCount > 0 else { return [:] }

        var remaining = maxCount
        var tracksByID: [String: [AMAlbumTrack]] = [:]
        for (index, album) in albums.enumerated() {
            if Task.isCancelled || remaining <= 0 { break }
            report("Reading album \(index + 1) of \(albums.count)…")

            guard let hydrated = try? await album.with(.tracks), let tracks = hydrated.tracks else {
                continue
            }

            let allTracks = await loadAll(tracks, max: remaining)
            let mapped = allTracks.enumerated().map { position, track in
                Self.makeAlbumTrack(track, albumID: album.id.rawValue, position: position)
            }
            if !mapped.isEmpty {
                tracksByID[album.id.rawValue] = mapped
                remaining -= mapped.count
            }
        }
        return tracksByID
    }

    private func loadAll<T: MusicItem & Decodable>(_ collection: MusicItemCollection<T>, max maxCount: Int) async -> [T] {
        var page = collection
        var all: [T] = Array(page.prefix(maxCount))
        while page.hasNextBatch, all.count < maxCount {
            let nextLimit = min(Self.pageSize, maxCount - all.count)
            guard let next = try? await page.nextBatch(limit: nextLimit) else { break }
            page = next
            all.append(contentsOf: next.prefix(maxCount - all.count))
        }
        return all
    }

    private func readNowPlaying() {
        let player = MPMusicPlayerController.systemMusicPlayer
        if let item = player.nowPlayingItem {
            nowPlayingTitle = item.title
            nowPlayingArtist = item.artist
        } else {
            nowPlayingTitle = nil
            nowPlayingArtist = nil
        }
    }

    private func updateAuthStatusText(_ status: MusicAuthorization.Status) {
        switch status {
        case .notDetermined: authorizationStatusText = "Not determined"
        case .denied: authorizationStatusText = "Denied"
        case .restricted: authorizationStatusText = "Restricted"
        case .authorized: authorizationStatusText = "Authorized"
        @unknown default: authorizationStatusText = "Unknown"
        }
    }

    private func report(_ message: String?) {
        syncProgress = message
    }

    // MARK: - Mapping

    fileprivate nonisolated static func makeTrack(_ song: Song) -> AMTrack {
        AMTrack(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            artistURL: song.artistURL?.absoluteString,
            attribution: song.attribution,
            composer: song.composerName,
            contentRating: song.contentRating.map { String(describing: $0) },
            discNumber: song.discNumber,
            duration: song.duration,
            editorialNotes: makeEditorialNotes(song.editorialNotes),
            genreNames: song.genreNames,
            hasLyrics: song.hasLyrics,
            audioVariants: audioVariants(song),
            isAppleDigitalMaster: appleDigitalMaster(song),
            isrc: song.isrc,
            lastPlayedDate: song.lastPlayedDate,
            libraryAddedDate: song.libraryAddedDate,
            playCount: song.playCount,
            movementCount: song.movementCount,
            movementName: song.movementName,
            movementNumber: song.movementNumber,
            previewAssets: song.previewAssets?.map(makePreviewAsset) ?? [],
            releaseDate: song.releaseDate,
            trackNumber: song.trackNumber,
            url: song.url?.absoluteString,
            workName: song.workName,
            artwork: makeArtwork(song.artwork)
        )
    }

    fileprivate nonisolated static func makeAlbum(_ album: Album) -> AMAlbum {
        AMAlbum(
            id: album.id.rawValue,
            title: album.title,
            artist: album.artistName,
            artistURL: album.artistURL?.absoluteString,
            contentRating: album.contentRating.map { String(describing: $0) },
            copyright: album.copyright,
            editorialNotes: makeEditorialNotes(album.editorialNotes),
            genreNames: album.genreNames,
            audioVariants: audioVariants(album),
            isAppleDigitalMaster: appleDigitalMaster(album),
            isCompilation: album.isCompilation,
            isComplete: album.isComplete,
            isSingle: album.isSingle,
            lastPlayedDate: album.lastPlayedDate,
            libraryAddedDate: album.libraryAddedDate,
            recordLabel: album.recordLabelName,
            releaseDate: album.releaseDate,
            trackCount: album.trackCount,
            upc: album.upc,
            url: album.url?.absoluteString,
            artwork: makeArtwork(album.artwork)
        )
    }

    fileprivate nonisolated static func makeAlbumTrack(_ track: Track, albumID: String, position: Int) -> AMAlbumTrack {
        let video = musicVideo(from: track)
        return AMAlbumTrack(
            id: track.id.rawValue,
            albumID: albumID,
            position: position,
            itemKind: trackKind(track),
            title: track.title,
            artist: track.artistName,
            albumTitle: track.albumTitle,
            artistURL: track.artistURL?.absoluteString,
            contentRating: track.contentRating.map { String(describing: $0) },
            discNumber: track.discNumber,
            duration: track.duration,
            editorialNotes: makeEditorialNotes(track.editorialNotes),
            genreNames: track.genreNames,
            lastPlayedDate: track.lastPlayedDate,
            libraryAddedDate: track.libraryAddedDate,
            playCount: track.playCount,
            isrc: track.isrc,
            playParametersDescription: track.playParameters.map { String(describing: $0) },
            previewAssets: track.previewAssets?.map(makePreviewAsset) ?? [],
            releaseDate: track.releaseDate,
            trackNumber: track.trackNumber,
            url: track.url?.absoluteString,
            workName: track.workName,
            artwork: makeArtwork(track.artwork),
            musicVideoHas4K: video?.has4K,
            musicVideoHasHDR: video?.hasHDR,
            musicVideoIsPreview: video?.isPreview,
            musicVideoStartTime: musicVideoStartTime(track),
            musicVideoEndTime: musicVideoEndTime(track)
        )
    }

    fileprivate nonisolated static func makeArtist(_ artist: Artist) -> AMArtist {
        AMArtist(
            id: artist.id.rawValue,
            name: artist.name,
            genreNames: artist.genreNames ?? [],
            libraryAddedDate: artist.libraryAddedDate,
            url: artist.url?.absoluteString,
            artwork: makeArtwork(artist.artwork),
            editorialNotes: makeEditorialNotes(artist.editorialNotes)
        )
    }

    fileprivate nonisolated static func makePlaylist(_ playlist: Playlist) -> AMPlaylist {
        AMPlaylist(
            id: playlist.id.rawValue,
            name: playlist.name,
            curator: playlist.curatorName,
            isChart: playlist.isChart,
            kind: playlist.kind.map { String(describing: $0) },
            lastModifiedDate: playlist.lastModifiedDate,
            lastPlayedDate: playlist.lastPlayedDate,
            libraryAddedDate: playlist.libraryAddedDate,
            shortDescription: playlist.shortDescription,
            standardDescription: playlist.standardDescription,
            url: playlist.url?.absoluteString,
            artwork: makeArtwork(playlist.artwork)
        )
    }

    fileprivate nonisolated static func makePlaylistEntry(_ entry: Playlist.Entry, playlistID: String) -> AMPlaylistEntry {
        let video = musicVideo(from: entry.item)
        return AMPlaylistEntry(
            id: entry.id.rawValue,
            itemID: entry.item?.id.rawValue,
            playlistID: playlistID,
            position: entry.position,
            itemKind: playlistEntryKind(entry.item),
            title: entry.title,
            artist: entry.artistName,
            albumTitle: entry.albumTitle,
            artistURL: entry.artistURL?.absoluteString,
            contentRating: entry.contentRating.map { String(describing: $0) },
            duration: entry.duration,
            editorialNotes: makeEditorialNotes(entry.editorialNotes),
            genreNames: entry.genreNames,
            lastPlayedDate: entry.lastPlayedDate,
            libraryAddedDate: entry.libraryAddedDate,
            playCount: entry.playCount,
            isrc: entry.isrc,
            playParametersDescription: entry.playParameters.map { String(describing: $0) },
            previewAssets: entry.previewAssets?.map(makePreviewAsset) ?? [],
            releaseDate: entry.releaseDate,
            url: entry.url?.absoluteString,
            artwork: makeArtwork(entry.artwork),
            musicVideoHas4K: video?.has4K,
            musicVideoHasHDR: video?.hasHDR,
            musicVideoIsPreview: video?.isPreview,
            musicVideoTrackNumber: video?.trackNumber,
            musicVideoWorkName: video?.workName,
            musicVideoStartTime: musicVideoStartTime(video),
            musicVideoEndTime: musicVideoEndTime(video)
        )
    }

    fileprivate nonisolated static func makeArtwork(_ artwork: Artwork?) -> AMArtwork? {
        guard let artwork else { return nil }
        return AMArtwork(
            url: artwork.url(width: artwork.maximumWidth, height: artwork.maximumHeight)?.absoluteString,
            maximumWidth: artwork.maximumWidth,
            maximumHeight: artwork.maximumHeight,
            alternateText: artwork.alternateText
        )
    }

    fileprivate nonisolated static func makeEditorialNotes(_ notes: EditorialNotes?) -> AMEditorialNotes? {
        guard let notes else { return nil }
        return AMEditorialNotes(
            short: notes.short,
            standard: notes.standard,
            name: notes.name,
            tagline: notes.tagline
        )
    }

    fileprivate nonisolated static func makePreviewAsset(_ asset: PreviewAsset) -> AMPreviewAsset {
        AMPreviewAsset(
            url: asset.url?.absoluteString,
            hlsURL: asset.hlsURL?.absoluteString,
            artwork: makeArtwork(asset.artwork)
        )
    }

    fileprivate nonisolated static func playlistEntryKind(_ item: Playlist.Entry.Item?) -> String {
        guard let item else { return "Unknown" }
        switch item {
        case .song: return "Song"
        case .musicVideo: return "Music Video"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func musicVideo(from item: Playlist.Entry.Item?) -> MusicVideo? {
        guard let item else { return nil }
        if case .musicVideo(let video) = item {
            return video
        }
        return nil
    }

    fileprivate nonisolated static func trackKind(_ track: Track) -> String {
        switch track {
        case .song: return "Song"
        case .musicVideo: return "Music Video"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func musicVideo(from track: Track) -> MusicVideo? {
        if case .musicVideo(let video) = track {
            return video
        }
        return nil
    }

    @available(iOS 26.4, *)
    fileprivate nonisolated static func availableMusicVideoStartTime(_ video: MusicVideo?) -> TimeInterval? {
        video?.startTime
    }

    @available(iOS 26.4, *)
    fileprivate nonisolated static func availableMusicVideoEndTime(_ video: MusicVideo?) -> TimeInterval? {
        video?.endTime
    }

    fileprivate nonisolated static func musicVideoStartTime(_ video: MusicVideo?) -> TimeInterval? {
        if #available(iOS 26.4, *) { return availableMusicVideoStartTime(video) }
        return nil
    }

    fileprivate nonisolated static func musicVideoEndTime(_ video: MusicVideo?) -> TimeInterval? {
        if #available(iOS 26.4, *) { return availableMusicVideoEndTime(video) }
        return nil
    }

    @available(iOS 26.4, *)
    fileprivate nonisolated static func availableMusicVideoStartTime(_ track: Track) -> TimeInterval? {
        track.startTime
    }

    @available(iOS 26.4, *)
    fileprivate nonisolated static func availableMusicVideoEndTime(_ track: Track) -> TimeInterval? {
        track.endTime
    }

    fileprivate nonisolated static func musicVideoStartTime(_ track: Track) -> TimeInterval? {
        if #available(iOS 26.4, *) { return availableMusicVideoStartTime(track) }
        return nil
    }

    fileprivate nonisolated static func musicVideoEndTime(_ track: Track) -> TimeInterval? {
        if #available(iOS 26.4, *) { return availableMusicVideoEndTime(track) }
        return nil
    }

    @available(iOS 16.0, *)
    fileprivate nonisolated static func availableAudioVariants(_ song: Song) -> [String] {
        (song.audioVariants ?? []).map { String(describing: $0) }
    }

    @available(iOS 16.0, *)
    fileprivate nonisolated static func availableAudioVariants(_ album: Album) -> [String] {
        (album.audioVariants ?? []).map { String(describing: $0) }
    }

    fileprivate nonisolated static func audioVariants(_ song: Song) -> [String] {
        if #available(iOS 16.0, *) { return availableAudioVariants(song) }
        return []
    }

    fileprivate nonisolated static func audioVariants(_ album: Album) -> [String] {
        if #available(iOS 16.0, *) { return availableAudioVariants(album) }
        return []
    }

    fileprivate nonisolated static func appleDigitalMaster(_ song: Song) -> Bool? {
        if #available(iOS 16.0, *) { return song.isAppleDigitalMaster }
        return nil
    }

    fileprivate nonisolated static func appleDigitalMaster(_ album: Album) -> Bool? {
        if #available(iOS 16.0, *) { return album.isAppleDigitalMaster }
        return nil
    }
}
