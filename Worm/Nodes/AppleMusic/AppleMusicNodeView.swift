import SwiftUI

/// Surfaces the Apple Music node: connect/disconnect, sync status, and a
/// readout of everything the node has pulled into memory.
struct AppleMusicNodeView: View {
    @Environment(AppleMusicNode.self) private var node

    var body: some View {
        List {
            statusSection

            if node.isAuthorized {
                snapshotSection
                accountSection
                granularSections
            } else {
                connectSection
            }

            if let error = node.lastErrorMessage {
                Section("Last error") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Apple Music")
        .toolbar {
            if node.isAuthorized {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await node.syncEverything() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(node.isSyncing)
                }
            }
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                if node.isSyncing || node.isAuthorizing {
                    ProgressView()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.statusSummary).font(.headline)
                    if let progress = node.syncProgress {
                        Text(progress).font(.caption).foregroundStyle(.secondary)
                    } else if let synced = node.lastSyncedAt {
                        Text("Last synced \(synced.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var connectSection: some View {
        Section {
            Button {
                Task { await node.connect() }
            } label: {
                Label("Connect Apple Music", systemImage: "music.note.list")
            }
            .disabled(node.isAuthorizing)
        } footer: {
            Text("Connecting grants read access to your Apple Music subscription, full library, recently played, recommendations, and now playing.")
        }
    }

    private var snapshotSection: some View {
        Section("Snapshot") {
            metric("Library songs", node.songs.count)
            metric("Library albums", node.albums.count)
            metric("Album tracks", node.albumTracksByID.values.reduce(0) { $0 + $1.count })
            metric("Library artists", node.artists.count)
            metric("Library playlists", node.playlists.count)
            metric("Playlist entries", node.playlistEntriesByID.values.reduce(0) { $0 + $1.count })
            metric("Playlists with entries", node.playlistEntriesByID.count)
            metric("Recently played", node.recentlyPlayed.count)
            metric("Recommendations", node.recommendations.count)
            metric("Songs with play count", node.songs.lazy.filter { $0.playCount != nil }.count)
            metric("Songs with last played", node.songs.lazy.filter { $0.lastPlayedDate != nil }.count)
            metric("Songs with genres", node.songs.lazy.filter { !$0.genreNames.isEmpty }.count)
            metric("Albums with labels", node.albums.lazy.filter { $0.recordLabel != nil }.count)
            metric("Playlist descriptions", node.playlists.lazy.filter { $0.shortDescription != nil || $0.standardDescription != nil }.count)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            labelled("Authorization", node.authorizationStatusText)
            labelled("Can play catalog", node.canPlayCatalogContent ? "Yes" : "No")
            labelled("Can subscribe", node.canBecomeSubscriber ? "Yes" : "No")
        }
    }

    @ViewBuilder
    private var granularSections: some View {
        if let title = node.nowPlayingTitle {
            Section("Now playing") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let artist = node.nowPlayingArtist {
                        Text(artist).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        trackNav("Recently played", node.recentlyPlayed)
        trackNav("Library songs", node.songs)

        if !node.albums.isEmpty {
            Section {
                NavigationLink("Library albums (\(node.albums.count))") {
                    List(node.albums) { album in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title)
                            Text(albumSubtitle(album)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Library albums")
                }
            }
        }

        if !node.artists.isEmpty {
            Section {
                NavigationLink("Library artists (\(node.artists.count))") {
                    List(node.artists) { Text($0.name) }
                        .navigationTitle("Library artists")
                }
            }
        }

        if !node.playlists.isEmpty {
            Section {
                NavigationLink("Library playlists (\(node.playlists.count))") {
                    List(node.playlists) { playlist in
                        NavigationLink {
                            AppleMusicPlaylistDetailView(
                                playlist: playlist,
                                entries: node.playlistEntriesByID[playlist.id] ?? []
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                Text(playlistSubtitle(playlist)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Library playlists")
                }
            }
        }

        if !node.recommendations.isEmpty {
            Section("Recommendations") {
                ForEach(node.recommendations) { recommendation in
                    HStack {
                        Text(recommendation.title)
                        Spacer()
                        Text("\(recommendation.itemCount)")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }

        Section {
            Button("Disconnect", role: .destructive) { node.disconnect() }
        }
    }

    // MARK: Builders

    @ViewBuilder
    private func trackNav(_ title: String, _ tracks: [AMTrack]) -> some View {
        if !tracks.isEmpty {
            Section {
                NavigationLink("\(title) (\(tracks.count))") {
                    List(tracks) { track in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                            Text(trackSubtitle(track)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle(title)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func trackSubtitle(_ track: AMTrack) -> String {
        var parts: [String] = [track.artist]
        if let album = track.album { parts.append(album) }
        if let playCount = track.playCount { parts.append("\(playCount) plays") }
        if let lastPlayed = track.lastPlayedDate {
            parts.append("last \(lastPlayed.formatted(date: .abbreviated, time: .omitted))")
        }
        if !track.genreNames.isEmpty { parts.append(track.genreNames.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " | ")
    }

    private func albumSubtitle(_ album: AMAlbum) -> String {
        var parts: [String] = [album.artist, "\(album.trackCount) tracks"]
        if let releaseDate = album.releaseDate {
            parts.append(releaseDate.formatted(date: .abbreviated, time: .omitted))
        }
        if let label = album.recordLabel { parts.append(label) }
        if !album.genreNames.isEmpty { parts.append(album.genreNames.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " | ")
    }

    private func playlistSubtitle(_ playlist: AMPlaylist) -> String {
        var parts: [String] = []
        if let entries = node.playlistEntriesByID[playlist.id] {
            parts.append("\(entries.count) entries")
        }
        if let curator = playlist.curator { parts.append(curator) }
        if let kind = playlist.kind { parts.append(kind) }
        if let modified = playlist.lastModifiedDate {
            parts.append("modified \(modified.formatted(date: .abbreviated, time: .omitted))")
        }
        if let description = playlist.shortDescription ?? playlist.standardDescription {
            parts.append(description)
        }
        return parts.isEmpty ? "Playlist" : parts.joined(separator: " | ")
    }
}

private struct AppleMusicPlaylistDetailView: View {
    let playlist: AMPlaylist
    let entries: [AMPlaylistEntry]

    var body: some View {
        List {
            Section("Playlist") {
                row("Name", playlist.name)
                row("Identifier", playlist.id)
                row("Curator", playlist.curator)
                row("Kind", playlist.kind)
                row("Entries", "\(entries.count)")
                row("Modified", playlist.lastModifiedDate?.formatted(date: .long, time: .standard))
                row("Last played", playlist.lastPlayedDate?.formatted(date: .long, time: .standard))
                row("Added", playlist.libraryAddedDate?.formatted(date: .long, time: .standard))
                row("URL", playlist.url)
                row("Description", playlist.shortDescription ?? playlist.standardDescription)
            }

            if !entries.isEmpty {
                Section("Entries") {
                    ForEach(entries.sorted { $0.position < $1.position }) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.position + 1). \(entry.title)")
                                .font(.subheadline)
                            Text(entrySubtitle(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(value).multilineTextAlignment(.trailing)
            }
        }
    }

    private func entrySubtitle(_ entry: AMPlaylistEntry) -> String {
        var parts: [String] = [entry.itemKind, entry.artist]
        if let album = entry.albumTitle { parts.append(album) }
        if let playCount = entry.playCount { parts.append("\(playCount) plays") }
        if let lastPlayed = entry.lastPlayedDate {
            parts.append("last \(lastPlayed.formatted(date: .abbreviated, time: .omitted))")
        }
        if let duration = entry.duration {
            parts.append(formatDuration(duration))
        }
        if !entry.genreNames.isEmpty {
            parts.append(entry.genreNames.prefix(2).joined(separator: ", "))
        }
        return parts.joined(separator: " | ")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

#Preview {
    NavigationStack {
        AppleMusicNodeView()
    }
    .environment(AppleMusicNode())
}
