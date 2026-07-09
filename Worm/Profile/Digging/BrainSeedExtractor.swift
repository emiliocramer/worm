import Foundation

/// Extracts typed, evidence-backed seeds from each node's structured data.
/// Deterministic and on-device, sibling to `SpotifyFeatureExtractor` and
/// `BrainDossier`. Slices carry the result the way they carry dossiers, so
/// `BrainContext` exposes structured entities without re-parsing prose.
///
/// The `@MainActor` entry points read node managers; the static cores take
/// plain collections so the logic stays testable.
enum BrainSeedExtractor {

    // MARK: - Spotify

    @MainActor
    static func seeds(for node: SpotifyMusicNode) -> [BrainSeed] {
        spotifySeeds(
            topArtistsShort: node.topArtistsShort,
            topArtistsMedium: node.topArtistsMedium,
            topArtistsLong: node.topArtistsLong,
            topTracksShort: node.topTracksShort,
            topTracksLong: node.topTracksLong,
            savedAlbums: node.savedAlbums,
            savedTrackCount: node.savedTracks.count,
            playlists: node.playlists.map(\.name),
            freshness: node.lastSyncedAt
        )
    }

    static func spotifySeeds(
        topArtistsShort: [SpotifyArtist],
        topArtistsMedium: [SpotifyArtist],
        topArtistsLong: [SpotifyArtist],
        topTracksShort: [SpotifyTrack],
        topTracksLong: [SpotifyTrack],
        savedAlbums: [SpotifySavedAlbum],
        savedTrackCount: Int,
        playlists: [String],
        freshness: Date?
    ) -> [BrainSeed] {
        var seeds: [BrainSeed] = []

        // Artist seeds, strength by durability across ranges.
        let shortNames = Set(topArtistsShort.map { $0.name.lowercased() })
        let mediumNames = Set(topArtistsMedium.map { $0.name.lowercased() })
        let longNames = Set(topArtistsLong.map { $0.name.lowercased() })
        var seenArtists = Set<String>()
        for artist in topArtistsLong + topArtistsShort where seenArtists.insert(artist.name.lowercased()).inserted {
            let key = artist.name.lowercased()
            let durable = shortNames.contains(key) && mediumNames.contains(key) && longNames.contains(key)
            let strength: Double
            var ranges: [String] = []
            if shortNames.contains(key) { ranges.append("short") }
            if mediumNames.contains(key) { ranges.append("medium") }
            if longNames.contains(key) { ranges.append("long") }
            switch ranges.count {
            case 3: strength = 0.9
            case 2: strength = 0.7
            default: strength = longNames.contains(key) ? 0.6 : 0.5
            }
            seeds.append(BrainSeed(
                sourceNode: .spotify,
                entityType: .artist,
                title: artist.name,
                subtitle: artist.genres?.prefix(2).joined(separator: ", "),
                evidence: ["top artist in \(ranges.joined(separator: "/")) range\(ranges.count == 1 ? "" : "s")\(durable ? ", every season" : "")"],
                strength: strength,
                freshness: freshness
            ))
            if seeds.count >= 14 { break }
        }

        // Label seeds from saved albums; majors are excluded because their
        // catalogs are the opposite of a diggable corner.
        var labelAlbums: [String: [String]] = [:]
        for saved in savedAlbums {
            guard let label = saved.album.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !label.isEmpty, !isMajorLabel(label) else { continue }
            labelAlbums[label, default: []].append(saved.album.name)
        }
        for (label, albums) in labelAlbums.sorted(by: { $0.value.count > $1.value.count }).prefix(6) {
            seeds.append(BrainSeed(
                sourceNode: .spotify,
                entityType: .label,
                title: label,
                subtitle: "label of \(albums.count) saved album\(albums.count == 1 ? "" : "s")",
                evidence: ["saved albums on \(label): \(albums.prefix(4).joined(separator: ", "))"],
                strength: min(0.95, 0.45 + 0.15 * Double(albums.count)),
                freshness: freshness
            ))
        }

        // Genre seeds from top artists' genre tags.
        var genreCounts: [String: Int] = [:]
        let genreSource = topArtistsShort.isEmpty ? topArtistsMedium : topArtistsShort
        for artist in genreSource {
            for genre in artist.genres ?? [] { genreCounts[genre, default: 0] += 1 }
        }
        let genreTotal = genreCounts.values.reduce(0, +)
        if genreTotal > 0 {
            for (genre, count) in genreCounts.sorted(by: { $0.value > $1.value }).prefix(6) {
                seeds.append(BrainSeed(
                    sourceNode: .spotify,
                    entityType: .genre,
                    title: genre,
                    subtitle: "\(Int(Double(count) / Double(genreTotal) * 100))% of top-artist genre tags",
                    evidence: ["\(count) of \(genreTotal) genre tags across current top artists"],
                    strength: min(0.95, 0.35 + Double(count) / Double(genreTotal) * 1.6),
                    freshness: freshness
                ))
            }
        }

        // Era seed: the tightest span of release years covering most listening.
        if let era = eraCluster(topTracksShort + topTracksLong) {
            seeds.append(BrainSeed(
                sourceNode: .spotify,
                entityType: .era,
                title: "\(era.range.lowerBound)-\(era.range.upperBound)",
                subtitle: "release-year cluster of top tracks",
                evidence: ["\(era.share)% of top-track release years fall in \(era.range.lowerBound)-\(era.range.upperBound)"],
                strength: min(0.95, Double(era.share) / 100 + 0.25),
                freshness: freshness
            ))
        }

        // Signal seeds the journey predicates read.
        let pops = topTracksShort.compactMap(\.popularity)
        if !pops.isEmpty {
            let mean = Double(pops.reduce(0, +)) / Double(pops.count)
            let obscureShare = Double(pops.filter { $0 < 30 }.count) / Double(pops.count)
            if mean < 38 || obscureShare > 0.35 {
                seeds.append(BrainSeed(
                    sourceNode: .spotify,
                    entityType: .aesthetic,
                    title: HeroJourney.SignalSeed.crateDigger,
                    subtitle: "low-popularity listening",
                    evidence: ["mean top-track popularity \(Int(mean)), \(Int(obscureShare * 100))% under 30"],
                    strength: min(0.95, 0.5 + (38 - min(mean, 38)) / 38 + obscureShare * 0.3),
                    freshness: freshness
                ))
            }
        }

        let liveMarkers = ["live at", "- live", "(live", "live in", "unplugged", "session"]
        let liveTitles = (topTracksShort + topTracksLong).map(\.name) + savedAlbums.map(\.album.name) + playlists
        let liveHits = liveTitles.filter { title in
            let lower = title.lowercased()
            return liveMarkers.contains(where: { lower.contains($0) })
        }
        if liveHits.count >= 4 {
            seeds.append(BrainSeed(
                sourceNode: .spotify,
                entityType: .aesthetic,
                title: HeroJourney.SignalSeed.liveRooms,
                subtitle: "live recordings recur",
                evidence: ["\(liveHits.count) live-marked titles, e.g. \(liveHits.prefix(3).joined(separator: "; "))"],
                strength: min(0.9, 0.5 + Double(liveHits.count) * 0.05),
                freshness: freshness
            ))
        }

        if savedAlbums.count >= 12, savedAlbums.count * 8 >= savedTrackCount {
            seeds.append(BrainSeed(
                sourceNode: .spotify,
                entityType: .aesthetic,
                title: HeroJourney.SignalSeed.albumListener,
                subtitle: "saves whole records",
                evidence: ["\(savedAlbums.count) saved albums against \(savedTrackCount) saved tracks"],
                strength: min(0.9, 0.5 + Double(savedAlbums.count) * 0.01),
                freshness: freshness
            ))
        }

        return seeds
    }

    // MARK: - Apple Music

    @MainActor
    static func seeds(for node: AppleMusicNode) -> [BrainSeed] {
        appleMusicSeeds(
            genreNames: node.songs.flatMap(\.genreNames),
            mostPlayed: node.songs
                .filter { ($0.playCount ?? 0) > 0 }
                .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
                .prefix(10)
                .map { ($0.artist, $0.playCount ?? 0) },
            freshness: node.lastSyncedAt
        )
    }

    static func appleMusicSeeds(
        genreNames: [String],
        mostPlayed: [(artist: String, playCount: Int)],
        freshness: Date?
    ) -> [BrainSeed] {
        var seeds: [BrainSeed] = []

        var genreCounts: [String: Int] = [:]
        for genre in genreNames where !genre.isEmpty && genre.lowercased() != "music" {
            genreCounts[genre, default: 0] += 1
        }
        let total = genreCounts.values.reduce(0, +)
        if total > 0 {
            for (genre, count) in genreCounts.sorted(by: { $0.value > $1.value }).prefix(5) {
                seeds.append(BrainSeed(
                    sourceNode: .appleMusic,
                    entityType: .genre,
                    title: genre,
                    subtitle: "library genre",
                    evidence: ["\(count) of \(total) library genre tags"],
                    strength: min(0.9, 0.3 + Double(count) / Double(total) * 1.4),
                    freshness: freshness
                ))
            }
        }

        var seen = Set<String>()
        for (artist, plays) in mostPlayed where !artist.isEmpty && seen.insert(artist.lowercased()).inserted {
            seeds.append(BrainSeed(
                sourceNode: .appleMusic,
                entityType: .artist,
                title: artist,
                subtitle: "heavy library rotation",
                evidence: ["\(plays) library plays"],
                strength: min(0.85, 0.5 + Double(plays) / 400),
                freshness: freshness
            ))
        }

        return seeds
    }

    // MARK: - YouTube

    @MainActor
    static func seeds(for node: YouTubeCultureNode) -> [BrainSeed] {
        let enriched = Array(node.enrichedVideosByID.values)
        return youtubeSeeds(
            creatorNames: (node.likedVideos + enriched).compactMap { $0.snippet?.channelTitle },
            topicCategories: (node.likedVideos + enriched).flatMap { $0.topicDetails?.topicCategories ?? [] }
                + node.enrichedChannelsByID.values.flatMap { $0.topicDetails?.topicCategories ?? [] },
            freshness: node.lastSyncedAt
        )
    }

    static func youtubeSeeds(
        creatorNames: [String],
        topicCategories: [String],
        freshness: Date?
    ) -> [BrainSeed] {
        var seeds: [BrainSeed] = []

        var creatorCounts: [String: Int] = [:]
        for name in creatorNames where !name.isEmpty {
            creatorCounts[name, default: 0] += 1
        }
        for (creator, count) in creatorCounts.sorted(by: { $0.value > $1.value }).prefix(8) where count >= 3 {
            seeds.append(BrainSeed(
                sourceNode: .youtube,
                entityType: .creator,
                title: creator,
                subtitle: "recurring creator",
                evidence: ["\(count) liked/enriched videos from \(creator)"],
                strength: min(0.9, 0.4 + Double(count) * 0.06),
                freshness: freshness
            ))
        }

        var topicCounts: [String: Int] = [:]
        for raw in topicCategories {
            let topic = raw.split(separator: "/").last.map(String.init) ?? raw
            let cleaned = topic.replacingOccurrences(of: "_", with: " ")
            guard !cleaned.isEmpty else { continue }
            topicCounts[cleaned, default: 0] += 1
        }
        for (topic, count) in topicCounts.sorted(by: { $0.value > $1.value }).prefix(6) where count >= 2 {
            seeds.append(BrainSeed(
                sourceNode: .youtube,
                entityType: .topic,
                title: topic,
                subtitle: "recurring video topic",
                evidence: ["\(count) videos/channels tagged \(topic)"],
                strength: min(0.85, 0.35 + Double(count) * 0.05),
                freshness: freshness
            ))
        }

        return seeds
    }

    // MARK: - Photos

    @MainActor
    static func seeds(for node: PhotosNode) -> [BrainSeed] {
        photosSeeds(
            locationNames: node.albums.flatMap(\.locationNames),
            freshness: node.lastSyncedAt
        )
    }

    static func photosSeeds(locationNames: [String], freshness: Date?) -> [BrainSeed] {
        var counts: [String: Int] = [:]
        for name in locationNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(6).map { place, count in
            BrainSeed(
                sourceNode: .photos,
                entityType: .place,
                title: place,
                subtitle: "photographed place",
                evidence: ["\(count) photo album location reference\(count == 1 ? "" : "s")"],
                strength: min(0.85, 0.35 + Double(count) * 0.08),
                freshness: freshness
            )
        }
    }

    // MARK: - Calendar

    @MainActor
    static func seeds(for node: CalendarNode) -> [BrainSeed] {
        calendarSeeds(
            recurringEvents: node.events
                .filter { $0.hasRecurrenceRules || !$0.recurrenceRules.isEmpty }
                .map { (title: $0.title, hour: Calendar.current.component(.hour, from: $0.startDate), isAllDay: $0.isAllDay) },
            freshness: node.lastSyncedAt
        )
    }

    static func calendarSeeds(
        recurringEvents: [(title: String, hour: Int, isAllDay: Bool)],
        freshness: Date?
    ) -> [BrainSeed] {
        var seeds: [BrainSeed] = []
        let timed = recurringEvents.filter { !$0.isAllDay }

        func routine(_ title: String, _ subtitle: String, matching: [(title: String, hour: Int, isAllDay: Bool)]) {
            guard matching.count >= 3 else { return }
            let examples = Array(Set(matching.map(\.title))).prefix(3).joined(separator: "; ")
            seeds.append(BrainSeed(
                sourceNode: .calendar,
                entityType: .routine,
                title: title,
                subtitle: subtitle,
                evidence: ["\(matching.count) recurring events, e.g. \(examples)"],
                strength: min(0.85, 0.4 + Double(matching.count) * 0.05),
                freshness: freshness
            ))
        }

        routine("late-night blocks", "recurring events at or after 21:00",
                matching: timed.filter { $0.hour >= 21 || $0.hour < 5 })
        routine("early-morning blocks", "recurring events between 5:00 and 8:00",
                matching: timed.filter { (5..<8).contains($0.hour) })

        let movementMarkers = ["gym", "run", "workout", "yoga", "climb", "swim", "ride", "walk"]
        routine("training routine", "recurring movement events",
                matching: recurringEvents.filter { event in
                    let lower = event.title.lowercased()
                    return movementMarkers.contains(where: { lower.contains($0) })
                })

        return seeds
    }

    // MARK: - Contacts

    @MainActor
    static func seeds(for node: ContactsNode) -> [BrainSeed] {
        contactsSeeds(
            cities: node.contacts.flatMap { $0.postalAddresses.map(\.city) },
            freshness: node.lastSyncedAt
        )
    }

    static func contactsSeeds(cities: [String], freshness: Date?) -> [BrainSeed] {
        var counts: [String: Int] = [:]
        for city in cities {
            let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(4).compactMap { city, count in
            guard count >= 2 else { return nil }
            return BrainSeed(
                sourceNode: .contacts,
                entityType: .place,
                title: city,
                subtitle: "where their people are",
                evidence: ["\(count) contacts with addresses in \(city)"],
                strength: min(0.6, 0.25 + Double(count) * 0.04),
                freshness: freshness
            )
        }
    }

    // MARK: - Selfie

    @MainActor
    static func seeds(for node: SelfieNode) -> [BrainSeed] {
        guard let analysis = node.analysis else { return [] }
        return selfieSeeds(
            aesthetics: analysis.aesthetics,
            confidence: analysis.confidence,
            freshness: node.lastAnalyzedAt
        )
    }

    static func selfieSeeds(aesthetics: [String], confidence: Double, freshness: Date?) -> [BrainSeed] {
        aesthetics.prefix(4).map { aesthetic in
            BrainSeed(
                sourceNode: .selfie,
                entityType: .aesthetic,
                title: aesthetic,
                subtitle: "observed in selfie",
                evidence: ["selfie read aesthetic signal: \(aesthetic)"],
                strength: min(0.7, confidence * 0.75),
                freshness: freshness
            )
        }
    }

    // MARK: - Helpers

    /// Majors and their umbrella imprints; their catalogs are not corners.
    private static let majorLabelMarkers: [String] = [
        "columbia", "rca", "atlantic", "interscope", "republic", "capitol",
        "epic", "island", "def jam", "geffen", "warner", "universal", "sony",
        "emi", "virgin", "arista", "polydor", "mercury", "elektra", "mca",
        "parlophone", "atlantic records", "big machine", "umg", "wea",
    ]

    static func isMajorLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        return majorLabelMarkers.contains(where: { lower.contains($0) })
    }

    /// The tightest contiguous span of release years holding at least 45% of
    /// top-track years, if the data supports one.
    static func eraCluster(_ tracks: [SpotifyTrack]) -> (range: ClosedRange<Int>, share: Int)? {
        let years = tracks.compactMap { track -> Int? in
            guard let date = track.album?.releaseDate, date.count >= 4 else { return nil }
            return Int(date.prefix(4))
        }.sorted()
        guard years.count >= 10 else { return nil }

        let need = Int((Double(years.count) * 0.45).rounded(.up))
        var best: (range: ClosedRange<Int>, count: Int)?
        var lower = 0
        for upper in years.indices {
            while years[upper] - years[lower] > 9 { lower += 1 }
            let count = upper - lower + 1
            if count >= need, count > (best?.count ?? 0) {
                best = (years[lower]...years[upper], count)
            }
        }
        guard let best else { return nil }
        return (best.range, Int(Double(best.count) / Double(years.count) * 100))
    }
}
