import Foundation

@MainActor
enum BrainSliceBuilder {
    static func context(
        spotify: SpotifyMusicNode? = nil,
        appleMusic: AppleMusicNode? = nil,
        youtube: YouTubeCultureNode? = nil,
        contacts: ContactsNode? = nil,
        photos: PhotosNode? = nil,
        calendar: CalendarNode? = nil,
        selfie: SelfieNode? = nil,
        read: String?,
        insights: [Insight]
    ) -> BrainContext {
        var slices: [NodeBrainSlice] = []
        if let spotify {
            slices.append(spotifySlice(spotify))
        } else {
            slices.append(emptySlice(.spotify))
        }
        if let appleMusic {
            slices.append(appleMusicSlice(appleMusic))
        } else {
            slices.append(emptySlice(.appleMusic))
        }
        if let youtube {
            slices.append(youtubeSlice(youtube))
        } else {
            slices.append(emptySlice(.youtube))
        }
        if let contacts {
            slices.append(contactsSlice(contacts))
        } else {
            slices.append(emptySlice(.contacts))
        }
        if let photos {
            slices.append(photosSlice(photos))
        } else {
            slices.append(emptySlice(.photos))
        }
        if let calendar {
            slices.append(calendarSlice(calendar))
        } else {
            slices.append(emptySlice(.calendar))
        }
        if let selfie {
            slices.append(selfieSlice(selfie))
        } else {
            slices.append(emptySlice(.selfie))
        }
        return BrainContext(slices: slices, read: read, insights: insights)
    }

    static func spotifySlice(from node: SpotifyMusicNode) -> NodeBrainSlice {
        spotifySlice(node)
    }

    static func selfieSlice(from node: SelfieNode) -> NodeBrainSlice {
        selfieSlice(node)
    }

    // MARK: - Slices

    private static func spotifySlice(_ node: SpotifyMusicNode) -> NodeBrainSlice {
        let features = SpotifyFeatureExtractor.extract(from: node)
        let populated = node.profile != nil ||
            !node.topTracksShort.isEmpty ||
            !node.topArtistsShort.isEmpty ||
            !node.savedTracks.isEmpty ||
            !node.playlists.isEmpty ||
            node.lastSyncedAt != nil

        var facts: [String] = []
        facts.append("profile: \(node.profile?.resolvedDisplayName ?? "unknown")")
        facts.append("top tracks: \(node.topTracksShort.count + node.topTracksMedium.count + node.topTracksLong.count)")
        facts.append("top artists: \(node.topArtistsShort.count + node.topArtistsMedium.count + node.topArtistsLong.count)")
        facts.append("saved tracks: \(node.savedTracks.count)")
        facts.append("playlists: \(node.playlists.count), hydrated tracks: \(node.hydratedPlaylistTrackCount)")
        if !features.topGenres.isEmpty { facts.append("dominant genres: \(features.topGenres.joined(separator: ", "))") }
        if !features.rideOrDie.isEmpty { facts.append("long-running artists: \(features.rideOrDie.joined(separator: ", "))") }
        if !features.newcomers.isEmpty { facts.append("new recent artists: \(features.newcomers.joined(separator: ", "))") }

        let evidence = features.briefText
            .split(separator: "\n")
            .prefix(18)
            .map(String.init)

        let chunks = [
            chunk("Recent favorite artists", features.recentTopArtists),
            chunk("All-time favorite artists", features.allTimeTopArtists),
            chunk("Playlist titles", features.playlistTitles),
            features.briefText,
        ].filter { !$0.isEmpty }

        return NodeBrainSlice(
            nodeID: .spotify,
            isConnected: node.isAuthorized,
            isPopulated: populated,
            summary: spotifySummary(node: node, features: features),
            facts: facts,
            evidence: evidence,
            chunks: Array(chunks.prefix(12)),
            freshness: node.lastSyncedAt,
            confidence: populated ? 0.9 : 0.0,
            health: node.isSyncing ? "syncing" : populated ? "ready" : node.isAuthorized ? "connected but empty" : "not connected",
            novelty: spotifyNovelty(node),
            dossier: populated ? BrainDossier.spotify(from: node) : nil
        )
    }

    private static func appleMusicSlice(_ node: AppleMusicNode) -> NodeBrainSlice {
        let populated = !node.songs.isEmpty ||
            !node.albums.isEmpty ||
            !node.artists.isEmpty ||
            !node.playlists.isEmpty ||
            !node.recentlyPlayed.isEmpty ||
            !node.recommendations.isEmpty ||
            node.lastSyncedAt != nil

        let genres = topCounts(node.songs.flatMap(\.genreNames), limit: 8)
        let playlistTitles = Array(node.playlists.prefix(30)).map(\.name)
        let recent = Array(node.recentlyPlayed.prefix(15)).map { "\($0.title) by \($0.artist)" }
        let topPlayed = node.songs
            .filter { $0.playCount != nil }
            .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
            .prefix(15)
            .map { "\($0.title) by \($0.artist) (\($0.playCount ?? 0) plays)" }

        var facts = [
            "library songs: \(node.songs.count)",
            "library albums: \(node.albums.count)",
            "library artists: \(node.artists.count)",
            "library playlists: \(node.playlists.count)",
            "playlist entries: \(node.playlistEntriesByID.values.reduce(0) { $0 + $1.count })",
            "recently played: \(node.recentlyPlayed.count)",
        ]
        if !genres.isEmpty { facts.append("library genres: \(genres.joined(separator: ", "))") }
        if node.canPlayCatalogContent { facts.append("can play catalog content") }

        let chunks = [
            chunk("Library genre distribution", genres),
            chunk("Recently played", recent),
            chunk("Most played library songs", topPlayed),
            chunk("Playlist titles", playlistTitles),
            chunk("Personal recommendation shelves", node.recommendations.map(\.title)),
        ].filter { !$0.isEmpty }

        return NodeBrainSlice(
            nodeID: .appleMusic,
            isConnected: node.isAuthorized,
            isPopulated: populated,
            summary: "Apple Music has \(node.songs.count) songs, \(node.albums.count) albums, \(node.playlists.count) playlists, and \(node.recentlyPlayed.count) recent plays.",
            facts: facts,
            evidence: Array(chunks.prefix(10)),
            chunks: Array(chunks.prefix(12)),
            freshness: node.lastSyncedAt,
            confidence: populated ? 0.82 : 0.0,
            health: node.isSyncing ? "syncing" : populated ? "ready" : node.isAuthorized ? "connected but empty" : "not connected",
            novelty: appleMusicNovelty(node),
            dossier: populated ? BrainDossier.appleMusic(from: node) : nil
        )
    }

    private static func youtubeSlice(_ node: YouTubeCultureNode) -> NodeBrainSlice {
        let populated = node.googleProfile != nil ||
            !node.channels.isEmpty ||
            !node.subscriptions.isEmpty ||
            !node.channelSections.isEmpty ||
            !node.activities.isEmpty ||
            !node.playlists.isEmpty ||
            !node.playlistItemsByID.isEmpty ||
            !node.uploadsPlaylistItemsByChannelID.isEmpty ||
            !node.likedVideos.isEmpty ||
            !node.enrichedVideosByID.isEmpty ||
            node.lastSyncedAt != nil

        let playlistItemCount = node.playlistItemCount
        let uploadItemCount = node.uploadItemCount
        let subscriptionTitles = Array(node.subscriptions.prefix(50))
            .compactMap { $0.snippet?.title }
        let playlistTitles = Array(node.playlists.prefix(50))
            .compactMap { $0.snippet?.title }
        let channelSectionTitles = Array(node.channelSections.prefix(30))
            .compactMap { $0.snippet?.title ?? $0.snippet?.type }
        let likedVideos = Array(node.likedVideos.prefix(50)).map { youtubeVideoLabel($0, categories: node.videoCategoriesByID) }

        let enrichedVideos = Array(node.enrichedVideosByID.values)
        let recurringCreators = topCounts(
            (node.likedVideos + enrichedVideos).compactMap { $0.snippet?.channelTitle },
            limit: 15
        )
        let videoCategories = topCounts(
            (node.likedVideos + enrichedVideos).compactMap { video in
                video.snippet?.categoryId.flatMap { node.videoCategoriesByID[$0]?.snippet?.title }
            },
            limit: 12
        )
        let topicCategories = topCounts(
            (node.likedVideos + enrichedVideos).flatMap { $0.topicDetails?.topicCategories ?? [] }
                + node.enrichedChannelsByID.values.flatMap { $0.topicDetails?.topicCategories ?? [] },
            limit: 12
        ).map(youtubeTopicName)
        let tags = topCounts(
            enrichedVideos.flatMap { $0.snippet?.tags ?? [] },
            limit: 18
        )
        let activityTypes = topCounts(
            node.activities.compactMap { $0.snippet?.type },
            limit: 8
        )
        let tasteTerms = topTerms(
            subscriptionTitles
                + playlistTitles
                + node.likedVideos.compactMap { $0.snippet?.title }
                + enrichedVideos.compactMap { $0.snippet?.title }
                + enrichedVideos.compactMap { $0.snippet?.description },
            limit: 24
        )

        var facts = [
            "google identity: \(node.googleProfile?.email ?? node.googleProfile?.name ?? "unknown")",
            "owned channels: \(node.channels.count)",
            "subscriptions: \(node.subscriptions.count)",
            "channel sections: \(node.channelSections.count)",
            "activities: \(node.activities.count)",
            "playlists: \(node.playlists.count)",
            "playlist items: \(playlistItemCount)",
            "upload items: \(uploadItemCount)",
            "liked videos: \(node.likedVideos.count)",
            "enriched videos: \(node.enrichedVideosByID.count)",
            "enriched channels: \(node.enrichedChannelsByID.count)",
        ]
        if !videoCategories.isEmpty { facts.append("video categories: \(videoCategories.joined(separator: ", "))") }
        if !recurringCreators.isEmpty { facts.append("recurring creators: \(recurringCreators.joined(separator: ", "))") }
        if !node.apiLimitations.isEmpty { facts.append("api limitations: \(node.apiLimitations.count)") }

        let limitations = node.apiLimitations.prefix(4).map { "YouTube API note: \($0)" }
        let chunks = [
            chunk("Subscribed YouTube channels", subscriptionTitles),
            chunk("YouTube playlist titles", playlistTitles),
            chunk("Liked YouTube videos", likedVideos),
            chunk("Recurring YouTube creators", recurringCreators),
            chunk("YouTube video categories", videoCategories),
            chunk("YouTube topic categories", topicCategories),
            chunk("YouTube tags", tags),
            chunk("YouTube activity types", activityTypes),
            chunk("YouTube channel sections", channelSectionTitles),
            chunk("Culture/title terms", tasteTerms),
        ].filter { !$0.isEmpty }

        return NodeBrainSlice(
            nodeID: .youtube,
            isConnected: node.isAuthorized,
            isPopulated: populated,
            summary: "YouTube has \(node.subscriptions.count) subscriptions, \(node.playlists.count) playlists, \(playlistItemCount) playlist items, \(node.likedVideos.count) liked videos, and \(node.enrichedVideosByID.count) enriched videos for culture taste.",
            facts: facts,
            evidence: Array((chunks + limitations).prefix(14)),
            chunks: Array((chunks + limitations).prefix(14)),
            freshness: node.lastSyncedAt,
            confidence: populated ? 0.78 : 0.0,
            health: node.isSyncing ? "syncing" : populated ? "ready" : node.isAuthorized ? "connected but empty" : "not connected",
            novelty: BrainNoveltySet()
        )
    }

    private static func contactsSlice(_ node: ContactsNode) -> NodeBrainSlice {
        let populated = !node.contacts.isEmpty ||
            !node.containers.isEmpty ||
            !node.groups.isEmpty ||
            node.lastSyncedAt != nil

        let phoneCount = node.contacts.reduce(0) { $0 + $1.phoneNumbers.count }
        let emailCount = node.contacts.reduce(0) { $0 + $1.emailAddresses.count }
        let postalCount = node.contacts.reduce(0) { $0 + $1.postalAddresses.count }
        let urlCount = node.contacts.reduce(0) { $0 + $1.urlAddresses.count }
        let relationCount = node.contacts.reduce(0) { $0 + $1.contactRelations.count }
        let socialCount = node.contacts.reduce(0) { $0 + $1.socialProfiles.count }
        let imCount = node.contacts.reduce(0) { $0 + $1.instantMessageAddresses.count }
        let birthdayCount = node.contacts.lazy.filter { $0.birthday != nil || $0.nonGregorianBirthday != nil }.count
        let imageCount = node.contacts.lazy.filter(\.image.imageDataAvailable).count

        let contactTypes = topCounts(node.contacts.map(\.contactType), limit: 4)
        let accountTypes = topCounts(node.containers.map(\.type), limit: 8)
        let accountNames = Array(node.containers.prefix(20)).map { container in
            let count = node.contactIDsByContainerID[container.id]?.count ?? 0
            return "\(container.name) (\(container.type), \(count))"
        }
        let groups = Array(node.groups.prefix(40)).map { group in
            let count = node.contactIDsByGroupID[group.id]?.count ?? 0
            return "\(group.name) (\(count))"
        }
        let contactLabels = Array(node.contacts.prefix(60)).map(contactBrainLabel)
        let organizations = topCounts(node.contacts.map(\.organizationName), limit: 20)
        let departments = topCounts(node.contacts.map(\.departmentName), limit: 16)
        let jobTitles = topCounts(node.contacts.map(\.jobTitle), limit: 18)
        let relationshipLabels = topCounts(
            node.contacts.flatMap { contact in
                contact.contactRelations.compactMap { $0.localizedLabel ?? $0.label }
            },
            limit: 14
        )
        let relationNames = topCounts(
            node.contacts.flatMap { contact in contact.contactRelations.map(\.name) },
            limit: 20
        )
        let socialServices = topCounts(
            node.contacts.flatMap { contact in contact.socialProfiles.compactMap(\.service) },
            limit: 12
        )
        let instantMessageServices = topCounts(
            node.contacts.flatMap { contact in contact.instantMessageAddresses.map(\.service) },
            limit: 12
        )
        let emailDomains = topCounts(
            node.contacts.flatMap { contact in contact.emailAddresses.compactMap { emailDomain($0.value) } },
            limit: 14
        )
        let urlHosts = topCounts(
            node.contacts.flatMap { contact in contact.urlAddresses.compactMap { urlHost($0.value) } },
            limit: 14
        )
        let postalCities = topCounts(
            node.contacts.flatMap { contact in
                contact.postalAddresses.flatMap { [$0.city, $0.state, $0.country] }
            },
            limit: 16
        )
        let dateLabels = topCounts(
            node.contacts.flatMap { contact in
                contact.dates.compactMap { $0.localizedLabel ?? $0.label }
            },
            limit: 12
        )
        let birthdayMonths = topCounts(
            node.contacts.compactMap { contact in
                (contact.birthday ?? contact.nonGregorianBirthday)?.month.map { "month \($0)" }
            },
            limit: 12
        )
        let nameTerms = topTerms(
            node.contacts.flatMap { contact in
                [
                    contact.displayName,
                    contact.nickname,
                    contact.organizationName,
                    contact.departmentName,
                    contact.jobTitle,
                ]
            },
            limit: 24
        )

        var facts = [
            "contacts: \(node.contacts.count)",
            "accounts: \(node.containers.count)",
            "groups: \(node.groups.count)",
            "phones: \(phoneCount)",
            "emails: \(emailCount)",
            "postal addresses: \(postalCount)",
            "urls: \(urlCount)",
            "relations: \(relationCount)",
            "social profiles: \(socialCount)",
            "instant messages: \(imCount)",
            "birthdays: \(birthdayCount)",
            "images: \(imageCount)",
        ]
        if !contactTypes.isEmpty { facts.append("contact types: \(contactTypes.joined(separator: ", "))") }
        if !accountTypes.isEmpty { facts.append("account types: \(accountTypes.joined(separator: ", "))") }
        if !node.apiLimitations.isEmpty { facts.append("api limitations: \(node.apiLimitations.count)") }

        let limitations = node.apiLimitations.prefix(4).map { "Contacts API note: \($0)" }
        let chunks = [
            chunk("Contact accounts", accountNames),
            chunk("Contact groups", groups),
            chunk("Representative contacts", contactLabels),
            chunk("Organizations in contacts", organizations),
            chunk("Departments in contacts", departments),
            chunk("Job titles in contacts", jobTitles),
            chunk("Relationship labels", relationshipLabels),
            chunk("Relationship names", relationNames),
            chunk("Social profile services", socialServices),
            chunk("Instant message services", instantMessageServices),
            chunk("Email domains", emailDomains),
            chunk("Contact URL hosts", urlHosts),
            chunk("Contact places", postalCities),
            chunk("Contact date labels", dateLabels),
            chunk("Birthday months", birthdayMonths),
            chunk("Name and affiliation terms", nameTerms),
        ].filter { !$0.isEmpty }

        return NodeBrainSlice(
            nodeID: .contacts,
            isConnected: node.isAuthorized,
            isPopulated: populated,
            summary: "Contacts has \(node.contacts.count) people/organizations across \(node.containers.count) accounts and \(node.groups.count) groups, with relationship labels, organizations, birthdays, social handles, and communication surfaces.",
            facts: facts,
            evidence: Array((chunks + limitations).prefix(14)),
            chunks: Array((chunks + limitations).prefix(16)),
            freshness: node.lastSyncedAt,
            confidence: populated ? 0.74 : 0.0,
            health: node.isSyncing ? "syncing" : populated ? "ready" : node.isAuthorized ? "connected but empty" : "not connected",
            novelty: BrainNoveltySet()
        )
    }

    private static func photosSlice(_ node: PhotosNode) -> NodeBrainSlice {
        let populated = !node.photos.isEmpty || !node.albums.isEmpty || node.lastSyncedAt != nil
        let classificationLabels = node.photos.flatMap { photo in
            photo.classifications.map { $0.components(separatedBy: " (").first ?? $0 }
        }
        let topClassifications = topCounts(classificationLabels, limit: 12)
        let albumTitles = Array(node.albums.prefix(30)).map(\.title)
        let locationNames = topCounts(node.albums.flatMap(\.locationNames), limit: 10)
        let withLocation = node.photos.lazy.filter { $0.latitude != nil }.count
        let withText = node.photos.lazy.filter { !$0.recognizedText.isEmpty }.count
        let withFaces = node.photos.lazy.filter { $0.faceCount > 0 }.count
        let videos = node.photos.lazy.filter { $0.mediaType == "Video" }.count

        let facts = [
            "assets: \(node.photos.count)",
            "albums: \(node.albums.count)",
            "videos: \(videos)",
            "with location: \(withLocation)",
            "with recognized text: \(withText)",
            "with faces: \(withFaces)",
            "favorites: \(node.photos.lazy.filter { $0.isFavorite }.count)",
            "edited: \(node.photos.lazy.filter { $0.hasAdjustments }.count)",
        ]

        let chunks = [
            chunk("Common visual classifications", topClassifications),
            chunk("Album titles", albumTitles),
            chunk("Album location names", locationNames),
        ].filter { !$0.isEmpty }

        return NodeBrainSlice(
            nodeID: .photos,
            isConnected: node.isAuthorized,
            isPopulated: populated,
            summary: "Photos has \(node.photos.count) assets with visual labels, OCR, faces, locations, and album structure summarized locally.",
            facts: facts,
            evidence: chunks,
            chunks: chunks,
            freshness: node.lastSyncedAt,
            confidence: populated ? 0.72 : 0.0,
            health: node.isSyncing ? "syncing" : populated ? "ready" : node.isAuthorized ? "connected but empty" : "not connected",
            novelty: BrainNoveltySet()
        )
    }

    private static func calendarSlice(_ node: CalendarNode) -> NodeBrainSlice {
        let populated = !node.sources.isEmpty ||
            !node.eventCalendars.isEmpty ||
            !node.reminderCalendars.isEmpty ||
            !node.events.isEmpty ||
            !node.reminders.isEmpty ||
            node.lastSyncedAt != nil

        let eventCalendars = Array(node.eventCalendars.prefix(20)).map(\.title)
        let reminderLists = Array(node.reminderCalendars.prefix(20)).map(\.title)
        let sourceTypes = topCounts(node.sources.map(\.type), limit: 8)
        let withAttendees = node.events.lazy.filter { !$0.attendees.isEmpty }.count
        let withLocation = node.events.lazy.filter { $0.location != nil || $0.structuredLocation != nil }.count
        let recurring = node.events.lazy.filter { !$0.recurrenceRules.isEmpty }.count
        let completedReminders = node.reminders.lazy.filter(\.isCompleted).count

        var facts = [
            "sources: \(node.sources.count)",
            "event calendars: \(node.eventCalendars.count)",
            "reminder lists: \(node.reminderCalendars.count)",
            "events: \(node.events.count)",
            "reminders: \(node.reminders.count)",
            "events with attendees: \(withAttendees)",
            "events with location: \(withLocation)",
            "recurring events: \(recurring)",
            "completed reminders: \(completedReminders)",
        ]
        if let start = node.scanStartDate, let end = node.scanEndDate {
            facts.append("event window: \(start.formatted(date: .abbreviated, time: .omitted)) to \(end.formatted(date: .abbreviated, time: .omitted))")
        }

        let chunks = [
            chunk("Calendar source types", sourceTypes),
            chunk("Event calendars", eventCalendars),
            chunk("Reminder lists", reminderLists),
            "Schedule shape: \(withAttendees) events include attendees, \(withLocation) include locations, \(recurring) are recurring.",
        ].filter { !$0.isEmpty }

        return NodeBrainSlice(
            nodeID: .calendar,
            isConnected: node.isAuthorized,
            isPopulated: populated,
            summary: "Calendar has \(node.events.count) events and \(node.reminders.count) reminders across \(node.eventCalendars.count) calendars and \(node.reminderCalendars.count) lists.",
            facts: facts,
            evidence: chunks,
            chunks: chunks,
            freshness: node.lastSyncedAt,
            confidence: populated ? 0.68 : 0.0,
            health: node.isSyncing ? "syncing" : populated ? "ready" : node.isAuthorized ? "connected but empty" : "not connected",
            novelty: BrainNoveltySet()
        )
    }

    private static func selfieSlice(_ node: SelfieNode) -> NodeBrainSlice {
        let analysis = node.analysis
        let populated = analysis != nil

        var facts: [String] = ["selfie captured: \(node.hasSelfie ? "yes" : "no")"]
        if let analysis {
            facts.append("read confidence: \(String(format: "%.2f", analysis.confidence))")
        }

        let chunks = [
            analysis.map { "Face read: \($0.read)" },
            analysis.map { "Standout observation: \($0.oneLiner)" },
            chunk("Observed in selfie", analysis?.observations ?? []),
            chunk("Aesthetic signals", analysis?.aesthetics ?? []),
        ].compactMap { $0 }.filter { !$0.isEmpty }

        return NodeBrainSlice(
            nodeID: .selfie,
            isConnected: node.hasSelfie,
            isPopulated: populated,
            summary: analysis?.read ?? "",
            facts: facts,
            evidence: chunks,
            chunks: chunks,
            freshness: node.lastAnalyzedAt,
            confidence: analysis?.confidence ?? 0,
            health: node.isAnalyzing ? "reading" : populated ? "ready" : node.hasSelfie ? "captured, not read" : "not connected",
            novelty: BrainNoveltySet()
        )
    }

    private static func emptySlice(_ id: BrainNodeID) -> NodeBrainSlice {
        NodeBrainSlice(
            nodeID: id,
            isConnected: false,
            isPopulated: false,
            summary: "",
            facts: [],
            evidence: [],
            chunks: [],
            freshness: nil,
            confidence: 0,
            health: "not available",
            novelty: BrainNoveltySet()
        )
    }

    // MARK: - Novelty

    private static func spotifyNovelty(_ node: SpotifyMusicNode) -> BrainNoveltySet {
        var novelty = BrainNoveltySet()

        func add(track: SpotifyTrack?) {
            guard let track else { return }
            novelty.insertTrack(title: track.name, artist: track.primaryArtist)
            novelty.insertAlbum(track.album?.name)
            track.artists.forEach { novelty.insertArtist($0.name) }
        }

        (node.topTracksShort + node.topTracksMedium + node.topTracksLong).forEach(add)
        node.savedTracks.map(\.track).forEach(add)
        node.recentlyPlayed.map(\.track).forEach(add)
        node.playlistItemsByID.values.flatMap { $0 }.compactMap(\.resolvedTrack).forEach(add)
        (node.topArtistsShort + node.topArtistsMedium + node.topArtistsLong + node.followedArtists)
            .forEach { novelty.insertArtist($0.name) }
        node.savedAlbums.forEach { album in
            novelty.insertAlbum(album.album.name)
            album.album.artists?.forEach { novelty.insertArtist($0.name) }
        }

        return BrainNoveltySet(
            knownTrackKeys: BrainNoveltySet.uniqued(novelty.knownTrackKeys),
            knownArtistKeys: BrainNoveltySet.uniqued(novelty.knownArtistKeys),
            knownAlbumKeys: BrainNoveltySet.uniqued(novelty.knownAlbumKeys)
        )
    }

    private static func appleMusicNovelty(_ node: AppleMusicNode) -> BrainNoveltySet {
        var novelty = BrainNoveltySet()

        func add(title: String?, artist: String?, album: String?) {
            novelty.insertTrack(title: title, artist: artist)
            novelty.insertArtist(artist)
            novelty.insertAlbum(album)
        }

        node.songs.forEach { add(title: $0.title, artist: $0.artist, album: $0.album) }
        node.recentlyPlayed.forEach { add(title: $0.title, artist: $0.artist, album: $0.album) }
        node.albumTracksByID.values.flatMap { $0 }.forEach { add(title: $0.title, artist: $0.artist, album: $0.albumTitle) }
        node.playlistEntriesByID.values.flatMap { $0 }.forEach { add(title: $0.title, artist: $0.artist, album: $0.albumTitle) }
        node.artists.forEach { novelty.insertArtist($0.name) }
        node.albums.forEach {
            novelty.insertAlbum($0.title)
            novelty.insertArtist($0.artist)
        }

        return BrainNoveltySet(
            knownTrackKeys: BrainNoveltySet.uniqued(novelty.knownTrackKeys),
            knownArtistKeys: BrainNoveltySet.uniqued(novelty.knownArtistKeys),
            knownAlbumKeys: BrainNoveltySet.uniqued(novelty.knownAlbumKeys)
        )
    }

    // MARK: - Helpers

    private static func spotifySummary(node: SpotifyMusicNode, features: TasteFeatures) -> String {
        var parts: [String] = []
        if let name = features.name { parts.append("Spotify profile for \(name)") }
        if !features.recentTopArtists.isEmpty {
            parts.append("recent favorites include \(features.recentTopArtists.prefix(5).joined(separator: ", "))")
        }
        if !features.topGenres.isEmpty {
            parts.append("dominant genres include \(features.topGenres.prefix(3).joined(separator: ", "))")
        }
        parts.append("\(node.savedTracks.count) saved tracks and \(node.playlists.count) playlists")
        return parts.joined(separator: "; ")
    }

    private static func chunk(_ label: String, _ values: [String]) -> String {
        guard !values.isEmpty else { return "" }
        return "\(label): \(values.prefix(40).joined(separator: ", "))"
    }

    private static func youtubeVideoLabel(_ video: YTVideo, categories: [String: YTVideoCategory]) -> String {
        var parts = [video.snippet?.title ?? video.id]
        if let channel = video.snippet?.channelTitle { parts.append(channel) }
        if let category = video.snippet?.categoryId.flatMap({ categories[$0]?.snippet?.title }) {
            parts.append(category)
        }
        return parts.joined(separator: " by ")
    }

    private static func youtubeTopicName(_ value: String) -> String {
        value
            .split(separator: "/")
            .last
            .map(String.init) ?? value
    }

    private static func contactBrainLabel(_ contact: ContactItem) -> String {
        var parts = [contact.displayName]
        if !contact.nickname.isEmpty { parts.append("nickname \(contact.nickname)") }
        if !contact.organizationName.isEmpty { parts.append(contact.organizationName) }
        if !contact.jobTitle.isEmpty { parts.append(contact.jobTitle) }
        if !contact.departmentName.isEmpty { parts.append(contact.departmentName) }
        let relations = contact.contactRelations
            .prefix(3)
            .map { "\($0.localizedLabel ?? $0.label ?? "relation") \($0.name)" }
        if !relations.isEmpty { parts.append("relations \(relations.joined(separator: "/"))") }
        if let city = contact.postalAddresses.first?.city, !city.isEmpty { parts.append(city) }
        if !contact.socialProfiles.isEmpty { parts.append("\(contact.socialProfiles.count) social") }
        return parts.joined(separator: " | ")
    }

    private static func emailDomain(_ value: String) -> String? {
        let parts = value.split(separator: "@")
        guard parts.count == 2 else { return nil }
        return String(parts[1]).lowercased()
    }

    private static func urlHost(_ value: String) -> String? {
        if let host = URLComponents(string: value)?.host, !host.isEmpty {
            return host.lowercased()
        }
        if let host = URLComponents(string: "https://\(value)")?.host, !host.isEmpty {
            return host.lowercased()
        }
        return nil
    }

    private static func topTerms(_ values: [String], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for value in values {
            guard let normalized = BrainNoveltySet.normalized(value) else { continue }
            for term in normalized.split(separator: " ").map(String.init) {
                guard term.count > 3, !termStopWords.contains(term) else { continue }
                counts[term, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(limit)
            .map { "\($0.key) (\($0.value))" }
    }

    private static func topCounts(_ values: [String], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }
        return counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(limit)
            .map { "\($0.key) (\($0.value))" }
    }

    private static let termStopWords: Set<String> = [
        "about", "after", "again", "also", "because", "been", "before",
        "being", "channel", "could", "from", "have", "into", "just",
        "like", "more", "music", "official", "only", "playlist", "that",
        "their", "there", "these", "they", "this", "through", "video",
        "watch", "what", "when", "where", "which", "with", "would", "your",
    ]
}
