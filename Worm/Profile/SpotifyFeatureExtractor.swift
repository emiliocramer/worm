import Foundation

/// Turns the Spotify node's raw data into a `TasteFeatures` brief.
///
/// This is the *feature* layer — cheap, deterministic, on-device. It does the
/// statistics (genre shares, era histogram, popularity, drift) and, crucially,
/// carries through the texture (artist names, playlist titles) untouched. It
/// does **not** author insights; that's the synthesizer's job.
enum SpotifyFeatureExtractor {
    @MainActor
    static func extract(from node: SpotifyMusicNode) -> TasteFeatures {
        var features = TasteFeatures()
        features.name = resolveName(node)

        let shortArtists = node.topArtistsShort
        let mediumArtists = node.topArtistsMedium
        let longArtists = node.topArtistsLong

        features.recentTopArtists = Array(shortArtists.prefix(15)).map(\.name)
        features.allTimeTopArtists = Array(longArtists.prefix(15)).map(\.name)

        // Ride-or-die: present in all three ranges.
        let s = Set(shortArtists.map { $0.name.lowercased() })
        let m = Set(mediumArtists.map { $0.name.lowercased() })
        features.rideOrDie = longArtists
            .filter { s.contains($0.name.lowercased()) && m.contains($0.name.lowercased()) }
            .prefix(5).map(\.name)

        // Newcomers: recent top-5 artists with no longer-term history.
        let established = Set((mediumArtists + longArtists).map { $0.name.lowercased() })
        features.newcomers = shortArtists.prefix(5)
            .filter { !established.contains($0.name.lowercased()) }
            .map(\.name)

        // Genre distribution (recent if available, else medium).
        let primaryArtists = shortArtists.isEmpty ? mediumArtists : shortArtists
        features.topGenres = topGenres(primaryArtists, limit: 5)

        // Genre drift: all-time share vs recent share.
        let (cooling, heating) = genreDrift(short: shortArtists, long: longArtists)
        features.coolingGenres = cooling
        features.heatingGenres = heating

        // Popularity of recent top tracks.
        let pops = node.topTracksShort.compactMap(\.popularity)
        if !pops.isEmpty {
            features.meanPopularity = Double(pops.reduce(0, +)) / Double(pops.count)
            let obscure = pops.filter { $0 < 30 }.count
            features.pctObscure = Double(obscure) / Double(pops.count) * 100
        }

        // Era histogram from top tracks' release years.
        features.eras = eraBuckets(node.topTracksShort + node.topTracksLong)

        // On-repeat + night owl from recently played.
        let recent = node.recentlyPlayed
        features.onRepeat = mostRepeated(recent)
        features.nightOwlRatio = nightOwl(recent)

        // Playlists the user owns (titles are gold for personality).
        if let me = node.profile?.id {
            let owned = node.playlists.filter { $0.owner?.id == me }
            features.ownedPlaylistCount = owned.count
            features.playlistTitles = Array(owned.prefix(30)).map(\.name)
        }

        features.savedTrackCount = node.savedTracks.count
        features.product = node.profile?.product

        return features
    }

    // MARK: - Helpers

    private static func tallyGenres(_ artists: [SpotifyArtist]) -> [(genre: String, count: Int)] {
        var counts: [String: Int] = [:]
        for artist in artists {
            for genre in artist.genres ?? [] { counts[genre, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private static func topGenres(_ artists: [SpotifyArtist], limit: Int) -> [String] {
        let tally = tallyGenres(artists)
        let total = tally.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        return tally.prefix(limit).map { "\($0.genre.capitalized) (\(Int(Double($0.count) / Double(total) * 100))%)" }
    }

    private static func genreDrift(short: [SpotifyArtist], long: [SpotifyArtist]) -> (cooling: [String], heating: [String]) {
        let shortTally = Dictionary(tallyGenres(short).map { ($0.genre, $0.count) }, uniquingKeysWith: { a, _ in a })
        let longTally = Dictionary(tallyGenres(long).map { ($0.genre, $0.count) }, uniquingKeysWith: { a, _ in a })
        let shortTotal = shortTally.values.reduce(0, +)
        let longTotal = longTally.values.reduce(0, +)
        guard shortTotal >= 5, longTotal >= 5 else { return ([], []) }

        var cooling: [(String, Double)] = []
        var heating: [(String, Double)] = []
        let genres = Set(shortTally.keys).union(longTally.keys)
        for genre in genres {
            let shortShare = Double(shortTally[genre] ?? 0) / Double(shortTotal)
            let longShare = Double(longTally[genre] ?? 0) / Double(longTotal)
            let delta = shortShare - longShare
            if delta <= -0.12 { cooling.append((genre, -delta)) }
            else if delta >= 0.12 { heating.append((genre, delta)) }
        }
        return (
            cooling.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0.capitalized },
            heating.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0.capitalized }
        )
    }

    private static func eraBuckets(_ tracks: [SpotifyTrack]) -> [String] {
        let years = tracks.compactMap { track -> Int? in
            guard let date = track.album?.releaseDate, date.count >= 4 else { return nil }
            return Int(date.prefix(4))
        }
        guard years.count >= 8 else { return [] }
        var decades: [Int: Int] = [:]
        for year in years { decades[(year / 10) * 10, default: 0] += 1 }
        return decades.sorted { $0.value > $1.value }.prefix(3).map {
            "\($0.key)s (\(Int(Double($0.value) / Double(years.count) * 100))%)"
        }
    }

    private static func mostRepeated(_ recent: [SpotifyRecentlyPlayedItem]) -> String? {
        guard recent.count >= 10 else { return nil }
        var counts: [String: Int] = [:]
        for item in recent { counts[item.track.id, default: 0] += 1 }
        guard let top = counts.max(by: { $0.value < $1.value }), top.value >= 3,
              let track = recent.first(where: { $0.track.id == top.key })?.track else { return nil }
        return "\(track.name) by \(track.primaryArtist) (\(top.value)×)"
    }

    private static func nightOwl(_ recent: [SpotifyRecentlyPlayedItem]) -> Double? {
        guard recent.count >= 12 else { return nil }
        let formatterFractional = ISO8601DateFormatter()
        formatterFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterPlain = ISO8601DateFormatter()
        let hours = recent.compactMap { item -> Int? in
            let date = formatterFractional.date(from: item.playedAt) ?? formatterPlain.date(from: item.playedAt)
            return date.map { Calendar.current.component(.hour, from: $0) }
        }
        guard hours.count >= 10 else { return nil }
        let late = hours.filter { $0 >= 22 || $0 < 5 }.count
        return Double(late) / Double(hours.count)
    }

    @MainActor
    private static func resolveName(_ node: SpotifyMusicNode) -> String? {
        if let stored = UserDefaults.standard.string(forKey: "worm.userName")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return stored
        }
        if let displayName = node.profile?.displayName, !displayName.isEmpty {
            return displayName.split(separator: " ").first.map(String.init)
        }
        return nil
    }
}
