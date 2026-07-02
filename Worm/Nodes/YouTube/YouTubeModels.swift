import Foundation

// MARK: - Auth / identity

struct GoogleAuthorizationTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let scopes: [String]
    let expirationDate: Date

    var needsRefresh: Bool {
        Date().addingTimeInterval(90) >= expirationDate
    }

    func refreshed(with response: GoogleTokenResponse) -> GoogleAuthorizationTokens {
        GoogleAuthorizationTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            tokenType: response.tokenType,
            scopes: response.scopeList.isEmpty ? scopes : response.scopeList,
            expirationDate: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }
}

struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }

    var scopeList: [String] {
        (scope ?? "")
            .split(separator: " ")
            .map(String.init)
            .sorted()
    }
}

struct GoogleUserInfo: Codable, Hashable {
    let sub: String?
    let name: String?
    let givenName: String?
    let familyName: String?
    let picture: String?
    let email: String?
    let emailVerified: Bool?
    let locale: String?

    enum CodingKeys: String, CodingKey {
        case sub
        case name
        case givenName = "given_name"
        case familyName = "family_name"
        case picture
        case email
        case emailVerified = "email_verified"
        case locale
    }
}

// MARK: - Shared YouTube primitives

struct YTPageInfo: Codable, Hashable {
    let totalResults: Int?
    let resultsPerPage: Int?
}

struct YTPagedResponse<Item: Codable & Hashable>: Codable, Hashable {
    let kind: String?
    let etag: String?
    let nextPageToken: String?
    let prevPageToken: String?
    let pageInfo: YTPageInfo?
    let items: [Item]
}

struct YTThumbnail: Codable, Hashable {
    let url: String?
    let width: Int?
    let height: Int?
}

struct YTLocalized: Codable, Hashable {
    let title: String?
    let description: String?
}

struct YTResourceID: Codable, Hashable {
    let kind: String?
    let videoId: String?
    let channelId: String?
    let playlistId: String?
}

struct YTTopicDetails: Codable, Hashable {
    let topicIds: [String]?
    let relevantTopicIds: [String]?
    let topicCategories: [String]?
}

// MARK: - Channels

struct YTChannel: Codable, Hashable, Identifiable {
    let kind: String?
    let etag: String?
    let id: String
    let snippet: YTChannelSnippet?
    let contentDetails: YTChannelContentDetails?
    let statistics: YTChannelStatistics?
    let topicDetails: YTTopicDetails?
    let status: YTChannelStatus?
    let brandingSettings: YTChannelBrandingSettings?
    let localizations: [String: YTLocalized]?
}

struct YTChannelSnippet: Codable, Hashable {
    let title: String?
    let description: String?
    let customUrl: String?
    let publishedAt: String?
    let thumbnails: [String: YTThumbnail]?
    let defaultLanguage: String?
    let localized: YTLocalized?
    let country: String?
}

struct YTChannelContentDetails: Codable, Hashable {
    let relatedPlaylists: YTRelatedPlaylists?
}

struct YTRelatedPlaylists: Codable, Hashable {
    let likes: String?
    let favorites: String?
    let uploads: String?
    let watchHistory: String?
    let watchLater: String?
}

struct YTChannelStatistics: Codable, Hashable {
    let viewCount: String?
    let subscriberCount: String?
    let hiddenSubscriberCount: Bool?
    let videoCount: String?
}

struct YTChannelStatus: Codable, Hashable {
    let privacyStatus: String?
    let isLinked: Bool?
    let longUploadsStatus: String?
    let madeForKids: Bool?
    let selfDeclaredMadeForKids: Bool?
}

struct YTChannelBrandingSettings: Codable, Hashable {
    let channel: YTBrandingChannel?
    let image: YTBrandingImage?
}

struct YTBrandingChannel: Codable, Hashable {
    let title: String?
    let description: String?
    let keywords: String?
    let trackingAnalyticsAccountId: String?
    let unsubscribedTrailer: String?
    let defaultLanguage: String?
    let country: String?
}

struct YTBrandingImage: Codable, Hashable {
    let bannerExternalUrl: String?
}

// MARK: - Subscriptions

struct YTSubscription: Codable, Hashable, Identifiable {
    let kind: String?
    let etag: String?
    let id: String
    let snippet: YTSubscriptionSnippet?
    let contentDetails: YTSubscriptionContentDetails?
    let subscriberSnippet: YTSubscriptionSubscriberSnippet?
}

struct YTSubscriptionSnippet: Codable, Hashable {
    let publishedAt: String?
    let title: String?
    let description: String?
    let resourceId: YTResourceID?
    let channelId: String?
    let thumbnails: [String: YTThumbnail]?
}

struct YTSubscriptionContentDetails: Codable, Hashable {
    let totalItemCount: Int?
    let newItemCount: Int?
    let activityType: String?
}

struct YTSubscriptionSubscriberSnippet: Codable, Hashable {
    let title: String?
    let description: String?
    let channelId: String?
    let thumbnails: [String: YTThumbnail]?
}

// MARK: - Playlists

struct YTPlaylist: Codable, Hashable, Identifiable {
    let kind: String?
    let etag: String?
    let id: String
    let snippet: YTPlaylistSnippet?
    let contentDetails: YTPlaylistContentDetails?
    let status: YTPlaylistStatus?
    let player: YTPlayer?
    let localizations: [String: YTLocalized]?
}

struct YTPlaylistSnippet: Codable, Hashable {
    let publishedAt: String?
    let channelId: String?
    let title: String?
    let description: String?
    let thumbnails: [String: YTThumbnail]?
    let channelTitle: String?
    let defaultLanguage: String?
    let localized: YTLocalized?
}

struct YTPlaylistContentDetails: Codable, Hashable {
    let itemCount: Int?
}

struct YTPlaylistStatus: Codable, Hashable {
    let privacyStatus: String?
}

struct YTPlaylistItem: Codable, Hashable, Identifiable {
    let kind: String?
    let etag: String?
    let id: String
    let snippet: YTPlaylistItemSnippet?
    let contentDetails: YTPlaylistItemContentDetails?
    let status: YTPlaylistItemStatus?

    var videoID: String? {
        contentDetails?.videoId ?? snippet?.resourceId?.videoId
    }
}

struct YTPlaylistItemSnippet: Codable, Hashable {
    let publishedAt: String?
    let channelId: String?
    let title: String?
    let description: String?
    let thumbnails: [String: YTThumbnail]?
    let channelTitle: String?
    let playlistId: String?
    let position: Int?
    let resourceId: YTResourceID?
    let videoOwnerChannelTitle: String?
    let videoOwnerChannelId: String?
}

struct YTPlaylistItemContentDetails: Codable, Hashable {
    let videoId: String?
    let startAt: String?
    let endAt: String?
    let note: String?
    let videoPublishedAt: String?
}

struct YTPlaylistItemStatus: Codable, Hashable {
    let privacyStatus: String?
}

struct YTPlayer: Codable, Hashable {
    let embedHtml: String?
}

// MARK: - Videos

struct YTVideo: Codable, Hashable, Identifiable {
    let kind: String?
    let etag: String?
    let id: String
    let snippet: YTVideoSnippet?
    let contentDetails: YTVideoContentDetails?
    let status: YTVideoStatus?
    let statistics: YTVideoStatistics?
    let topicDetails: YTTopicDetails?
    let recordingDetails: YTVideoRecordingDetails?
    let liveStreamingDetails: YTLiveStreamingDetails?
    let player: YTPlayer?
    let localizations: [String: YTLocalized]?
    let paidProductPlacementDetails: YTPaidProductPlacementDetails?
}

struct YTVideoSnippet: Codable, Hashable {
    let publishedAt: String?
    let channelId: String?
    let title: String?
    let description: String?
    let thumbnails: [String: YTThumbnail]?
    let channelTitle: String?
    let tags: [String]?
    let categoryId: String?
    let liveBroadcastContent: String?
    let defaultLanguage: String?
    let localized: YTLocalized?
    let defaultAudioLanguage: String?
}

struct YTVideoContentDetails: Codable, Hashable {
    let duration: String?
    let dimension: String?
    let definition: String?
    let caption: String?
    let licensedContent: Bool?
    let projection: String?
    let hasCustomThumbnail: Bool?
    let regionRestriction: YTRegionRestriction?
    let contentRating: [String: String]?
}

struct YTRegionRestriction: Codable, Hashable {
    let allowed: [String]?
    let blocked: [String]?
}

struct YTVideoStatus: Codable, Hashable {
    let uploadStatus: String?
    let failureReason: String?
    let rejectionReason: String?
    let privacyStatus: String?
    let publishAt: String?
    let license: String?
    let embeddable: Bool?
    let publicStatsViewable: Bool?
    let madeForKids: Bool?
    let selfDeclaredMadeForKids: Bool?
}

struct YTVideoStatistics: Codable, Hashable {
    let viewCount: String?
    let likeCount: String?
    let favoriteCount: String?
    let commentCount: String?
}

struct YTVideoRecordingDetails: Codable, Hashable {
    let recordingDate: String?
    let locationDescription: String?
}

struct YTLiveStreamingDetails: Codable, Hashable {
    let actualStartTime: String?
    let actualEndTime: String?
    let scheduledStartTime: String?
    let scheduledEndTime: String?
    let concurrentViewers: String?
    let activeLiveChatId: String?
}

struct YTPaidProductPlacementDetails: Codable, Hashable {
    let hasPaidProductPlacement: Bool?
}

struct YTVideoCategory: Codable, Hashable, Identifiable {
    let kind: String?
    let etag: String?
    let id: String
    let snippet: YTVideoCategorySnippet?
}

struct YTVideoCategorySnippet: Codable, Hashable {
    let channelId: String?
    let title: String?
    let assignable: Bool?
}

// MARK: - Activities and channel sections

struct YTActivity: Codable, Hashable, Identifiable {
    let kind: String?
    let etag: String?
    let id: String
    let snippet: YTActivitySnippet?
    let contentDetails: YTActivityContentDetails?
}

struct YTActivitySnippet: Codable, Hashable {
    let publishedAt: String?
    let channelId: String?
    let title: String?
    let description: String?
    let thumbnails: [String: YTThumbnail]?
    let channelTitle: String?
    let type: String?
    let groupId: String?
}

struct YTActivityContentDetails: Codable, Hashable {
    let upload: YTActivityUpload?
    let like: YTActivityLike?
    let favorite: YTActivityFavorite?
    let playlistItem: YTActivityPlaylistItem?
    let recommendation: YTActivityRecommendation?
    let social: YTActivitySocial?
    let subscription: YTActivitySubscription?
    let bulletin: YTActivityBulletin?
    let channelItem: YTActivityChannelItem?
}

struct YTActivityUpload: Codable, Hashable {
    let videoId: String?
}

struct YTActivityLike: Codable, Hashable {
    let resourceId: YTResourceID?
}

struct YTActivityFavorite: Codable, Hashable {
    let resourceId: YTResourceID?
}

struct YTActivityPlaylistItem: Codable, Hashable {
    let resourceId: YTResourceID?
    let playlistId: String?
    let playlistItemId: String?
}

struct YTActivityRecommendation: Codable, Hashable {
    let resourceId: YTResourceID?
    let reason: String?
    let seedResourceId: YTResourceID?
}

struct YTActivitySocial: Codable, Hashable {
    let type: String?
    let resourceId: YTResourceID?
    let author: String?
    let referenceUrl: String?
    let imageUrl: String?
}

struct YTActivitySubscription: Codable, Hashable {
    let resourceId: YTResourceID?
}

struct YTActivityBulletin: Codable, Hashable {
    let resourceId: YTResourceID?
}

struct YTActivityChannelItem: Codable, Hashable {
    let resourceId: YTResourceID?
}

struct YTChannelSection: Codable, Hashable, Identifiable {
    let kind: String?
    let etag: String?
    let id: String
    let snippet: YTChannelSectionSnippet?
    let contentDetails: YTChannelSectionContentDetails?
    let localizations: [String: YTLocalized]?
}

struct YTChannelSectionSnippet: Codable, Hashable {
    let type: String?
    let style: String?
    let channelId: String?
    let title: String?
    let position: Int?
    let defaultLanguage: String?
    let localized: YTLocalized?
}

struct YTChannelSectionContentDetails: Codable, Hashable {
    let playlists: [String]?
    let channels: [String]?
}

// MARK: - Snapshot

struct YouTubeCultureNodeSnapshot: Codable {
    let googleProfile: GoogleUserInfo?
    let channels: [YTChannel]
    let subscriptions: [YTSubscription]
    let channelSections: [YTChannelSection]
    let activities: [YTActivity]
    let playlists: [YTPlaylist]
    let playlistItemsByID: [String: [YTPlaylistItem]]
    let uploadsPlaylistItemsByChannelID: [String: [YTPlaylistItem]]
    let likedVideos: [YTVideo]
    let enrichedVideosByID: [String: YTVideo]
    let enrichedChannelsByID: [String: YTChannel]
    let videoCategoriesByID: [String: YTVideoCategory]
    let grantedScopes: [String]
    let apiLimitations: [String]
    let lastSyncedAt: Date?
}
