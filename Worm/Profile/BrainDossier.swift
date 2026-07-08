import Foundation

/// Builds the item-level evidence document the synthesizer reads. Deterministic and
/// on-device, like `SpotifyFeatureExtractor` — but where the extractor distills, the
/// dossier preserves texture: track titles with release years and popularity, rank
/// movement across time ranges, saved-at timelines, play timestamps. This is the raw
/// material an "oh shit, it knows me" observation is made from; counts alone can't do it.
@MainActor
enum BrainDossier {

    // MARK: - Spotify

    static func spotify(from node: SpotifyMusicNode) -> String {
        var sections: [String] = []
        let artistPopularity = artistPopularityIndex(node)

        func trackLine(_ track: SpotifyTrack, rank: Int? = nil) -> String {
            var parts: [String] = []
            if let rank { parts.append("\(rank).") }
            parts.append("\(track.name) — \(track.primaryArtist)")
            var meta: [String] = []
            if let year = releaseYear(track) { meta.append(String(year)) }
            if let pop = track.popularity { meta.append("popularity \(pop)") }
            if let flag = deepCutFlag(track, artistPopularity: artistPopularity) { meta.append(flag) }
            if !meta.isEmpty { parts.append("(\(meta.joined(separator: ", ")))") }
            return parts.joined(separator: " ")
        }

        func trackSection(_ title: String, _ tracks: [SpotifyTrack], limit: Int) -> String? {
            guard !tracks.isEmpty else { return nil }
            let lines = tracks.prefix(limit).enumerated().map { trackLine($0.element, rank: $0.offset + 1) }
            return "\(title):\n" + lines.joined(separator: "\n")
        }

        func artistSection(_ title: String, _ artists: [SpotifyArtist], limit: Int) -> String? {
            guard !artists.isEmpty else { return nil }
            let lines = artists.prefix(limit).enumerated().map { index, artist -> String in
                var meta: [String] = []
                if let genres = artist.genres, !genres.isEmpty { meta.append(genres.prefix(3).joined(separator: "/")) }
                if let pop = artist.popularity { meta.append("popularity \(pop)") }
                let suffix = meta.isEmpty ? "" : " (\(meta.joined(separator: ", ")))"
                return "\(index + 1). \(artist.name)\(suffix)"
            }
            return "\(title):\n" + lines.joined(separator: "\n")
        }

        sections.append(contentsOf: [
            trackSection("Top tracks, last ~4 weeks", node.topTracksShort, limit: 25),
            trackSection("Top tracks, last ~6 months", node.topTracksMedium, limit: 20),
            trackSection("Top tracks, all time", node.topTracksLong, limit: 30),
            artistSection("Top artists, last ~4 weeks", node.topArtistsShort, limit: 15),
            artistSection("Top artists, all time", node.topArtistsLong, limit: 15),
        ].compactMap { $0 })

        sections.append(contentsOf: rankMovement(node))
        if let saved = savedTimeline(node) { sections.append(saved) }
        if let recent = recentPlays(node) { sections.append(recent) }
        if let playlists = playlistShelf(node) { sections.append(playlists) }

        // The distilled brief still earns its place: genre shares, drift, eras,
        // popularity stats that would take the model effort to recompute.
        let brief = SpotifyFeatureExtractor.extract(from: node).briefText
        if !brief.isEmpty { sections.append("Computed features:\n" + brief) }

        return sections.joined(separator: "\n\n")
    }

    // MARK: Spotify sections

    /// Cross-range facts the model shouldn't have to reconstruct. Stated neutrally:
    /// interpretation is the hunt stage's job. Editorial framing here gets
    /// paraphrased straight into lines, which reads as a data summary in a costume.
    private static func rankMovement(_ node: SpotifyMusicNode) -> [String] {
        var sections: [String] = []
        let shortNames = Set(node.topArtistsShort.map { $0.name.lowercased() })
        let mediumNames = Set(node.topArtistsMedium.map { $0.name.lowercased() })

        let faded = node.topArtistsLong.prefix(15).filter {
            !shortNames.contains($0.name.lowercased()) && !mediumNames.contains($0.name.lowercased())
        }
        if !faded.isEmpty {
            sections.append("All-time top artists not present in the 4-week or 6-month record: "
                + faded.map(\.name).joined(separator: ", "))
        }

        let shortTrackKeys = Set(node.topTracksShort.map { $0.name.lowercased() })
        let durable = node.topTracksLong.prefix(30).filter { shortTrackKeys.contains($0.name.lowercased()) }
        if !durable.isEmpty {
            sections.append("Tracks in both the all-time and 4-week top: "
                + durable.map { "\($0.name) — \($0.primaryArtist)" }.joined(separator: "; "))
        }

        var trackCounts: [String: (artist: String, tracks: [String])] = [:]
        for track in node.topTracksLong {
            let key = track.primaryArtist.lowercased()
            trackCounts[key, default: (track.primaryArtist, [])].tracks.append(track.name)
        }
        let oneSong = trackCounts.values
            .filter { $0.tracks.count == 1 }
            .sorted { $0.artist < $1.artist }
            .prefix(12)
            .map { "\($0.tracks[0]) — \($0.artist)" }
        if oneSong.count >= 3 {
            sections.append("Artists appearing in the all-time top tracks by exactly one track: "
                + oneSong.joined(separator: "; "))
        }

        return sections
    }

    private static func savedTimeline(_ node: SpotifyMusicNode) -> String? {
        guard !node.savedTracks.isEmpty else { return nil }
        let dated = node.savedTracks.compactMap { saved -> (date: Date, track: SpotifyTrack)? in
            guard let date = parseISO(saved.addedAt) else { return nil }
            return (date, saved.track)
        }
        guard !dated.isEmpty else { return nil }

        var lines: [String] = []
        let recent = dated.sorted { $0.date > $1.date }.prefix(20).map {
            "\(shortDate($0.date)): \($0.track.name) — \($0.track.primaryArtist)"
        }
        lines.append("Most recent saves:\n" + recent.joined(separator: "\n"))

        var byMonth: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        for item in dated { byMonth[formatter.string(from: item.date), default: 0] += 1 }
        if byMonth.count > 1 {
            let histogram = byMonth.sorted { $0.key > $1.key }.prefix(18)
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            lines.append("Saves per month: \(histogram)")
        }

        if let oldest = dated.min(by: { $0.date < $1.date }) {
            lines.append("Oldest save on record: \(shortDate(oldest.date)): \(oldest.track.name) — \(oldest.track.primaryArtist)")
        }
        return "Saved-track timeline (library saves with dates):\n" + lines.joined(separator: "\n")
    }

    private static func recentPlays(_ node: SpotifyMusicNode) -> String? {
        guard !node.recentlyPlayed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        let lines = node.recentlyPlayed.prefix(25).map { item -> String in
            let when = parseISO(item.playedAt).map { formatter.string(from: $0) } ?? "?"
            return "\(when): \(item.track.name) — \(item.track.primaryArtist)"
        }
        var counts: [String: Int] = [:]
        for item in node.recentlyPlayed { counts[item.track.name, default: 0] += 1 }
        let repeats = counts.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.prefix(6)
            .map { "\($0.key) (\($0.value)×)" }
        var section = "Recent play log (local day/time):\n" + lines.joined(separator: "\n")
        if !repeats.isEmpty { section += "\nRepeats in the log: " + repeats.joined(separator: ", ") }
        return section
    }

    private static func playlistShelf(_ node: SpotifyMusicNode) -> String? {
        guard !node.playlists.isEmpty else { return nil }
        let me = node.profile?.id
        let owned = node.playlists.filter { $0.owner?.id == me }
        let followed = node.playlists.count - owned.count
        guard !owned.isEmpty || followed > 0 else { return nil }
        var lines: [String] = []
        if !owned.isEmpty {
            let entries = owned.prefix(30).map { playlist -> String in
                var meta: [String] = []
                if let total = playlist.tracks?.total { meta.append("\(total) tracks") }
                if playlist.collaborative == true { meta.append("collaborative") }
                let suffix = meta.isEmpty ? "" : " (\(meta.joined(separator: ", ")))"
                return "- \(playlist.name)\(suffix)"
            }
            lines.append("Playlists they built:\n" + entries.joined(separator: "\n"))
        }
        if followed > 0 { lines.append("Playlists followed but not built: \(followed)") }
        return lines.joined(separator: "\n")
    }

    private static func artistPopularityIndex(_ node: SpotifyMusicNode) -> [String: Int] {
        var index: [String: Int] = [:]
        for artist in node.topArtistsShort + node.topArtistsMedium + node.topArtistsLong {
            if let pop = artist.popularity { index[artist.name.lowercased()] = pop }
        }
        return index
    }

    /// Flags a track markedly less popular than its artist. Stated as numbers, not
    /// a verdict — whether it is a deep cut worth mentioning is the hunt's call.
    private static func deepCutFlag(_ track: SpotifyTrack, artistPopularity: [String: Int]) -> String? {
        guard let trackPop = track.popularity,
              let artistPop = artistPopularity[track.primaryArtist.lowercased()],
              artistPop - trackPop >= 25 else { return nil }
        return "artist popularity \(artistPop)"
    }

    // MARK: - Apple Music

    static func appleMusic(from node: AppleMusicNode) -> String {
        var sections: [String] = []

        let topPlayed = node.songs
            .filter { ($0.playCount ?? 0) > 0 }
            .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
            .prefix(25)
            .enumerated()
            .map { index, song -> String in
                var meta = ["\(song.playCount ?? 0) plays"]
                if let year = song.releaseDate.map({ Calendar.current.component(.year, from: $0) }) {
                    meta.append(String(year))
                }
                if let added = song.libraryAddedDate { meta.append("added \(shortDate(added))") }
                return "\(index + 1). \(song.title) — \(song.artist) (\(meta.joined(separator: ", ")))"
            }
        if !topPlayed.isEmpty {
            sections.append("Most played library songs (lifetime play counts):\n" + topPlayed.joined(separator: "\n"))
        }

        let recent = node.recentlyPlayed.prefix(20).map { "\($0.title) — \($0.artist)" }
        if !recent.isEmpty {
            sections.append("Recently played:\n" + recent.joined(separator: "\n"))
        }

        let additions = node.songs
            .compactMap { song in song.libraryAddedDate.map { (date: $0, song: song) } }
            .sorted { $0.date > $1.date }
            .prefix(15)
            .map { "\(shortDate($0.date)): \($0.song.title) — \($0.song.artist)" }
        if !additions.isEmpty {
            sections.append("Most recent library additions:\n" + additions.joined(separator: "\n"))
        }

        let playlists = node.playlists.prefix(25).map { playlist -> String in
            let count = node.playlistEntriesByID[playlist.id]?.count
            let suffix = count.map { " (\($0) tracks)" } ?? ""
            return "- \(playlist.name)\(suffix)"
        }
        if !playlists.isEmpty {
            sections.append("Library playlists:\n" + playlists.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    private static func releaseYear(_ track: SpotifyTrack) -> Int? {
        guard let date = track.album?.releaseDate, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func parseISO(_ value: String) -> Date? {
        isoFractional.date(from: value) ?? isoPlain.date(from: value)
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
