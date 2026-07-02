import Foundation

// MARK: - Auth

struct SpotifyAuthorizationTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let scopes: [String]
    let expirationDate: Date

    var needsRefresh: Bool {
        Date().addingTimeInterval(90) >= expirationDate
    }

    func refreshed(with response: SpotifyTokenResponse) -> SpotifyAuthorizationTokens {
        SpotifyAuthorizationTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            tokenType: response.tokenType,
            scopes: response.scopeList.isEmpty ? scopes : response.scopeList,
            expirationDate: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }
}

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int
    let refreshToken: String?

    var scopeList: [String] {
        (scope ?? "")
            .split(separator: " ")
            .map(String.init)
            .sorted()
    }
}

// MARK: - Shared primitives

struct SpotifyExternalURLs: Codable, Hashable {
    let spotify: String?
}

struct SpotifyImage: Codable, Hashable {
    let url: String
    let height: Int?
    let width: Int?
}

struct SpotifyFollowers: Codable, Hashable {
    let total: Int?
}

struct SpotifyExternalIDs: Codable, Hashable {
    let isrc: String?
    let ean: String?
    let upc: String?
}

struct SpotifyRestrictions: Codable, Hashable {
    let reason: String?
}

struct SpotifyCopyright: Codable, Hashable {
    let text: String?
    let type: String?
}

// MARK: - Artists & albums

struct SpotifyArtist: Codable, Hashable, Identifiable {
    let id: String?
    let name: String
    let href: String?
    let type: String?
    let uri: String?
    let genres: [String]?
    let popularity: Int?
    let followers: SpotifyFollowers?
    let images: [SpotifyImage]?
    let externalUrls: SpotifyExternalURLs?

    var artworkURL: URL? {
        images?.first.flatMap { URL(string: $0.url) }
    }
}

struct SpotifyAlbum: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let href: String?
    let type: String?
    let albumType: String?
    let albumGroup: String?
    let totalTracks: Int?
    let availableMarkets: [String]?
    let releaseDate: String?
    let releaseDatePrecision: String?
    let label: String?
    let genres: [String]?
    let popularity: Int?
    let copyrights: [SpotifyCopyright]?
    let externalIds: SpotifyExternalIDs?
    let restrictions: SpotifyRestrictions?
    let artists: [SpotifyArtist]?
    let images: [SpotifyImage]
    let uri: String?
    let externalUrls: SpotifyExternalURLs?

    var artworkURL: URL? {
        images.first.flatMap { URL(string: $0.url) }
    }
}

// MARK: - Tracks

struct SpotifyTrack: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let href: String?
    let type: String?
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    let availableMarkets: [String]?
    let durationMs: Int?
    let explicit: Bool?
    let externalIds: SpotifyExternalIDs?
    let isLocal: Bool?
    let popularity: Int?
    let restrictions: SpotifyRestrictions?
    let trackNumber: Int?
    let discNumber: Int?
    let previewUrl: String?
    let uri: String?
    let externalUrls: SpotifyExternalURLs?

    var primaryArtist: String {
        artists.first?.name ?? "Unknown Artist"
    }

    var artistLine: String {
        let names = artists.map(\.name)
        return names.isEmpty ? "Unknown Artist" : names.joined(separator: ", ")
    }

    var artworkURL: URL? {
        album?.images.first.flatMap { URL(string: $0.url) }
    }

    var spotifyURL: URL? {
        externalUrls?.spotify.flatMap(URL.init(string:))
    }
}

// MARK: - Profile

struct SpotifyUserProfile: Codable {
    let id: String
    let displayName: String?
    let email: String?
    let product: String?
    let country: String?
    let followers: SpotifyFollowers?
    let externalUrls: SpotifyExternalURLs?
    let images: [SpotifyImage]

    var resolvedDisplayName: String {
        displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? displayName!
            : id
    }

    var artworkURL: URL? {
        images.first.flatMap { URL(string: $0.url) }
    }
}

struct SpotifyUserProfileReference: Codable, Hashable {
    let id: String?
    let displayName: String?
    let href: String?
    let type: String?
    let uri: String?
    let externalUrls: SpotifyExternalURLs?
}

// MARK: - Playback

struct SpotifyPlaybackContext: Codable, Hashable {
    let type: String?
    let uri: String?
    let href: String?
    let externalUrls: SpotifyExternalURLs?
}

struct SpotifyPlaybackDevice: Codable, Hashable {
    let id: String?
    let isActive: Bool?
    let isPrivateSession: Bool?
    let isRestricted: Bool?
    let name: String?
    let type: String?
    let volumePercent: Int?
    let supportsVolume: Bool?
}

struct SpotifyCurrentPlayback: Codable {
    let context: SpotifyPlaybackContext?
    let timestamp: Int?
    let progressMs: Int?
    let isPlaying: Bool?
    let currentlyPlayingType: String?
    let shuffleState: Bool?
    let repeatState: String?
    let item: SpotifyPlayableItem?
    let device: SpotifyPlaybackDevice?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        context = try container.decodeIfPresent(SpotifyPlaybackContext.self, forKey: .context)
        timestamp = try container.decodeIfPresent(Int.self, forKey: .timestamp)
        progressMs = try container.decodeIfPresent(Int.self, forKey: .progressMs)
        isPlaying = try container.decodeIfPresent(Bool.self, forKey: .isPlaying)
        currentlyPlayingType = try container.decodeIfPresent(String.self, forKey: .currentlyPlayingType)
        shuffleState = try container.decodeIfPresent(Bool.self, forKey: .shuffleState)
        repeatState = try container.decodeIfPresent(String.self, forKey: .repeatState)
        device = try container.decodeIfPresent(SpotifyPlaybackDevice.self, forKey: .device)
        item = try? container.decode(SpotifyPlayableItem.self, forKey: .item)
    }
}

// MARK: - Library items

struct SpotifySavedTrack: Codable, Hashable, Identifiable {
    let addedAt: String
    let track: SpotifyTrack

    var id: String { track.id }
}

struct SpotifySavedAlbum: Codable, Hashable, Identifiable {
    let addedAt: String?
    let album: SpotifyAlbum

    var id: String { album.id }
}

struct SpotifyRecentlyPlayedItem: Codable, Hashable, Identifiable {
    let track: SpotifyTrack
    let playedAt: String
    let context: SpotifyPlaybackContext?

    var id: String { "\(track.id)|\(playedAt)" }
}

// MARK: - Shows, episodes, audiobooks

struct SpotifyShow: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let href: String?
    let type: String?
    let availableMarkets: [String]?
    let copyrights: [SpotifyCopyright]?
    let publisher: String?
    let description: String?
    let htmlDescription: String?
    let languages: [String]?
    let mediaType: String?
    let totalEpisodes: Int?
    let explicit: Bool?
    let isExternallyHosted: Bool?
    let images: [SpotifyImage]
    let uri: String?
    let externalUrls: SpotifyExternalURLs?
}

struct SpotifySavedShow: Codable, Hashable, Identifiable {
    let addedAt: String?
    let show: SpotifyShow

    var id: String { show.id }
}

struct SpotifyEpisode: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let href: String?
    let type: String?
    let audioPreviewUrl: String?
    let description: String?
    let htmlDescription: String?
    let durationMs: Int?
    let releaseDate: String?
    let releaseDatePrecision: String?
    let explicit: Bool?
    let isExternallyHosted: Bool?
    let isPlayable: Bool?
    let language: String?
    let languages: [String]?
    let resumePoint: SpotifyResumePoint?
    let images: [SpotifyImage]
    let uri: String?
    let externalUrls: SpotifyExternalURLs?
}

struct SpotifyResumePoint: Codable, Hashable {
    let fullyPlayed: Bool?
    let resumePositionMs: Int?
}

struct SpotifyUnknownPlayable: Codable, Hashable {
    let id: String?
    let name: String?
    let type: String?
    let uri: String?
}

enum SpotifyPlayableItem: Codable, Hashable, Identifiable {
    case track(SpotifyTrack)
    case episode(SpotifyEpisode)
    case unknown(SpotifyUnknownPlayable)

    var id: String {
        switch self {
        case .track(let track):
            return "track:\(track.id)"
        case .episode(let episode):
            return "episode:\(episode.id)"
        case .unknown(let item):
            return "unknown:\(item.id ?? item.uri ?? item.name ?? "item")"
        }
    }

    var displayTitle: String {
        switch self {
        case .track(let track):
            return track.name
        case .episode(let episode):
            return episode.name
        case .unknown(let item):
            return item.name ?? "Unknown item"
        }
    }

    var displaySubtitle: String {
        switch self {
        case .track(let track):
            return track.artistLine
        case .episode(let episode):
            return episode.releaseDate ?? "Episode"
        case .unknown(let item):
            return item.type ?? "Unknown"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try? container.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "track":
            self = .track(try SpotifyTrack(from: decoder))
        case "episode":
            self = .episode(try SpotifyEpisode(from: decoder))
        default:
            self = .unknown(try SpotifyUnknownPlayable(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .track(let track):
            try track.encode(to: encoder)
        case .episode(let episode):
            try episode.encode(to: encoder)
        case .unknown(let item):
            try item.encode(to: encoder)
        }
    }
}

struct SpotifySavedEpisode: Codable, Hashable, Identifiable {
    let addedAt: String?
    let episode: SpotifyEpisode

    var id: String { episode.id }
}

struct SpotifyAudiobook: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let href: String?
    let type: String?
    let authors: [SpotifyNamed]?
    let narrators: [SpotifyNamed]?
    let availableMarkets: [String]?
    let copyrights: [SpotifyCopyright]?
    let publisher: String?
    let description: String?
    let htmlDescription: String?
    let languages: [String]?
    let mediaType: String?
    let totalChapters: Int?
    let explicit: Bool?
    let images: [SpotifyImage]
    let uri: String?
    let externalUrls: SpotifyExternalURLs?
}

struct SpotifyChapter: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let href: String?
    let type: String?
    let audioPreviewUrl: String?
    let availableMarkets: [String]?
    let chapterNumber: Int?
    let description: String?
    let htmlDescription: String?
    let durationMs: Int?
    let explicit: Bool?
    let isPlayable: Bool?
    let languages: [String]?
    let releaseDate: String?
    let releaseDatePrecision: String?
    let resumePoint: SpotifyResumePoint?
    let images: [SpotifyImage]
    let uri: String?
    let externalUrls: SpotifyExternalURLs?
}

struct SpotifyNamed: Codable, Hashable {
    let name: String
}

// MARK: - Playlists

struct SpotifyPlaylist: Codable, Hashable, Identifiable {
    struct TracksSummary: Codable, Hashable {
        let total: Int
    }

    let id: String
    let name: String
    let href: String?
    let type: String?
    let description: String?
    let collaborative: Bool?
    let `public`: Bool?
    let primaryColor: String?
    let snapshotId: String?
    let owner: SpotifyUserProfileReference?
    let images: [SpotifyImage]
    let externalUrls: SpotifyExternalURLs?
    let tracks: TracksSummary?
    let uri: String?

    var artworkURL: URL? {
        images.first.flatMap { URL(string: $0.url) }
    }

    var spotifyURL: URL? {
        externalUrls?.spotify.flatMap(URL.init(string:))
    }
}

struct SpotifyPlaylistItem: Codable, Hashable {
    let addedAt: String?
    let addedBy: SpotifyUserProfileReference?
    let track: SpotifyTrack?
    let item: SpotifyTrack?
    let isLocal: Bool?

    var resolvedTrack: SpotifyTrack? {
        track ?? item
    }
}

// MARK: - Pagination envelopes

struct SpotifyPagedResponse<Item: Decodable>: Decodable {
    let items: [Item]
    let limit: Int?
    let offset: Int?
    let total: Int?
    let next: String?
    let previous: String?
}

struct SpotifyTrackSearchResponse: Decodable {
    let tracks: SpotifyPagedResponse<SpotifyTrack>
}

/// Cursor-based pagination (used by followed artists), wrapped under an
/// `artists` key in the response.
struct SpotifyFollowedArtistsResponse: Decodable {
    struct Page: Decodable {
        let items: [SpotifyArtist]
        let next: String?
        let total: Int?
        let cursors: Cursors?
    }

    struct Cursors: Decodable {
        let after: String?
    }

    let artists: Page
}

struct SpotifyRecentlyPlayedResponse: Decodable {
    let items: [SpotifyRecentlyPlayedItem]
    let next: String?
}

struct SpotifyDevicesResponse: Decodable {
    let devices: [SpotifyPlaybackDevice]
}

struct SpotifyQueueResponse: Codable, Hashable {
    let currentlyPlaying: SpotifyPlayableItem?
    let queue: [SpotifyPlayableItem]
}

// MARK: - Persisted snapshot

/// The full in-memory state of the Spotify node, persisted to disk so a
/// returning user sees their data instantly instead of re-fetching everything.
struct SpotifyNodeSnapshot: Codable {
    let profile: SpotifyUserProfile?
    let currentlyPlaying: SpotifyCurrentPlayback?
    let playbackState: SpotifyCurrentPlayback?
    let availableDevices: [SpotifyPlaybackDevice]
    let queue: SpotifyQueueResponse?
    let recentlyPlayed: [SpotifyRecentlyPlayedItem]
    let topTracksShort: [SpotifyTrack]
    let topTracksMedium: [SpotifyTrack]
    let topTracksLong: [SpotifyTrack]
    let topArtistsShort: [SpotifyArtist]
    let topArtistsMedium: [SpotifyArtist]
    let topArtistsLong: [SpotifyArtist]
    let savedTracks: [SpotifySavedTrack]
    let savedAlbums: [SpotifySavedAlbum]
    let savedShows: [SpotifySavedShow]
    let savedEpisodes: [SpotifySavedEpisode]
    let savedAudiobooks: [SpotifyAudiobook]
    let savedAlbumTracksByID: [String: [SpotifyTrack]]
    let savedShowEpisodesByID: [String: [SpotifyEpisode]]
    let savedAudiobookChaptersByID: [String: [SpotifyChapter]]
    let followedArtists: [SpotifyArtist]
    let playlists: [SpotifyPlaylist]
    let playlistItemsByID: [String: [SpotifyPlaylistItem]]
    let grantedScopes: [String]
    let lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case profile
        case currentlyPlaying
        case playbackState
        case availableDevices
        case queue
        case recentlyPlayed
        case topTracksShort
        case topTracksMedium
        case topTracksLong
        case topArtistsShort
        case topArtistsMedium
        case topArtistsLong
        case savedTracks
        case savedAlbums
        case savedShows
        case savedEpisodes
        case savedAudiobooks
        case savedAlbumTracksByID
        case savedShowEpisodesByID
        case savedAudiobookChaptersByID
        case followedArtists
        case playlists
        case playlistItemsByID
        case grantedScopes
        case lastSyncedAt
    }

    init(
        profile: SpotifyUserProfile?,
        currentlyPlaying: SpotifyCurrentPlayback?,
        playbackState: SpotifyCurrentPlayback?,
        availableDevices: [SpotifyPlaybackDevice],
        queue: SpotifyQueueResponse?,
        recentlyPlayed: [SpotifyRecentlyPlayedItem],
        topTracksShort: [SpotifyTrack],
        topTracksMedium: [SpotifyTrack],
        topTracksLong: [SpotifyTrack],
        topArtistsShort: [SpotifyArtist],
        topArtistsMedium: [SpotifyArtist],
        topArtistsLong: [SpotifyArtist],
        savedTracks: [SpotifySavedTrack],
        savedAlbums: [SpotifySavedAlbum],
        savedShows: [SpotifySavedShow],
        savedEpisodes: [SpotifySavedEpisode],
        savedAudiobooks: [SpotifyAudiobook],
        savedAlbumTracksByID: [String: [SpotifyTrack]],
        savedShowEpisodesByID: [String: [SpotifyEpisode]],
        savedAudiobookChaptersByID: [String: [SpotifyChapter]],
        followedArtists: [SpotifyArtist],
        playlists: [SpotifyPlaylist],
        playlistItemsByID: [String: [SpotifyPlaylistItem]],
        grantedScopes: [String],
        lastSyncedAt: Date?
    ) {
        self.profile = profile
        self.currentlyPlaying = currentlyPlaying
        self.playbackState = playbackState
        self.availableDevices = availableDevices
        self.queue = queue
        self.recentlyPlayed = recentlyPlayed
        self.topTracksShort = topTracksShort
        self.topTracksMedium = topTracksMedium
        self.topTracksLong = topTracksLong
        self.topArtistsShort = topArtistsShort
        self.topArtistsMedium = topArtistsMedium
        self.topArtistsLong = topArtistsLong
        self.savedTracks = savedTracks
        self.savedAlbums = savedAlbums
        self.savedShows = savedShows
        self.savedEpisodes = savedEpisodes
        self.savedAudiobooks = savedAudiobooks
        self.savedAlbumTracksByID = savedAlbumTracksByID
        self.savedShowEpisodesByID = savedShowEpisodesByID
        self.savedAudiobookChaptersByID = savedAudiobookChaptersByID
        self.followedArtists = followedArtists
        self.playlists = playlists
        self.playlistItemsByID = playlistItemsByID
        self.grantedScopes = grantedScopes
        self.lastSyncedAt = lastSyncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(SpotifyUserProfile.self, forKey: .profile)
        currentlyPlaying = try container.decodeIfPresent(SpotifyCurrentPlayback.self, forKey: .currentlyPlaying)
        playbackState = try container.decodeIfPresent(SpotifyCurrentPlayback.self, forKey: .playbackState)
        availableDevices = try container.decodeIfPresent([SpotifyPlaybackDevice].self, forKey: .availableDevices) ?? []
        queue = try container.decodeIfPresent(SpotifyQueueResponse.self, forKey: .queue)
        recentlyPlayed = try container.decodeIfPresent([SpotifyRecentlyPlayedItem].self, forKey: .recentlyPlayed) ?? []
        topTracksShort = try container.decodeIfPresent([SpotifyTrack].self, forKey: .topTracksShort) ?? []
        topTracksMedium = try container.decodeIfPresent([SpotifyTrack].self, forKey: .topTracksMedium) ?? []
        topTracksLong = try container.decodeIfPresent([SpotifyTrack].self, forKey: .topTracksLong) ?? []
        topArtistsShort = try container.decodeIfPresent([SpotifyArtist].self, forKey: .topArtistsShort) ?? []
        topArtistsMedium = try container.decodeIfPresent([SpotifyArtist].self, forKey: .topArtistsMedium) ?? []
        topArtistsLong = try container.decodeIfPresent([SpotifyArtist].self, forKey: .topArtistsLong) ?? []
        savedTracks = try container.decodeIfPresent([SpotifySavedTrack].self, forKey: .savedTracks) ?? []
        savedAlbums = try container.decodeIfPresent([SpotifySavedAlbum].self, forKey: .savedAlbums) ?? []
        savedShows = try container.decodeIfPresent([SpotifySavedShow].self, forKey: .savedShows) ?? []
        savedEpisodes = try container.decodeIfPresent([SpotifySavedEpisode].self, forKey: .savedEpisodes) ?? []
        savedAudiobooks = try container.decodeIfPresent([SpotifyAudiobook].self, forKey: .savedAudiobooks) ?? []
        savedAlbumTracksByID = try container.decodeIfPresent([String: [SpotifyTrack]].self, forKey: .savedAlbumTracksByID) ?? [:]
        savedShowEpisodesByID = try container.decodeIfPresent([String: [SpotifyEpisode]].self, forKey: .savedShowEpisodesByID) ?? [:]
        savedAudiobookChaptersByID = try container.decodeIfPresent([String: [SpotifyChapter]].self, forKey: .savedAudiobookChaptersByID) ?? [:]
        followedArtists = try container.decodeIfPresent([SpotifyArtist].self, forKey: .followedArtists) ?? []
        playlists = try container.decodeIfPresent([SpotifyPlaylist].self, forKey: .playlists) ?? []
        playlistItemsByID = try container.decodeIfPresent([String: [SpotifyPlaylistItem]].self, forKey: .playlistItemsByID) ?? [:]
        grantedScopes = try container.decodeIfPresent([String].self, forKey: .grantedScopes) ?? []
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
    }
}
