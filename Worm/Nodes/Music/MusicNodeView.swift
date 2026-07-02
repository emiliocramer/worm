import SwiftUI

/// Surfaces the Spotify music node: connect/disconnect, sync status, and a
/// readout of everything the node has pulled into memory.
struct MusicNodeView: View {
    @Environment(SpotifyMusicNode.self) private var node

    var body: some View {
        List {
            statusSection

            if node.isAuthorized {
                snapshotSection
                profileSection
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
        .navigationTitle("Music Node")
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
                Label("Connect Spotify", systemImage: "music.note")
            }
            .disabled(!node.isConfigured || node.isAuthorizing)

            if !node.isConfigured, let message = node.configurationMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } footer: {
            Text("Connecting grants read access to your full Spotify profile, listening history, taste, library, follows, and playlists.")
        }
    }

    private var snapshotSection: some View {
        Section("Snapshot") {
            metric("Saved tracks", node.savedTracks.count)
            metric("Saved albums", node.savedAlbums.count)
            metric("Saved shows", node.savedShows.count)
            metric("Saved episodes", node.savedEpisodes.count)
            metric("Saved audiobooks", node.savedAudiobooks.count)
            metric("Saved album tracks", node.savedAlbumTracksByID.values.reduce(0) { $0 + $1.count })
            metric("Saved show episodes", node.savedShowEpisodesByID.values.reduce(0) { $0 + $1.count })
            metric("Saved audiobook chapters", node.savedAudiobookChaptersByID.values.reduce(0) { $0 + $1.count })
            metric("Followed artists", node.followedArtists.count)
            metric("Available devices", node.availableDevices.count)
            metric("Queue items", node.queue?.queue.count ?? 0)
            metric("Recently played", node.recentlyPlayed.count)
            metric("Playlists", node.playlists.count)
            metric("Playlist tracks", node.hydratedPlaylistTrackCount)
            metric("Top tracks (S/M/L)", node.topTracksShort.count + node.topTracksMedium.count + node.topTracksLong.count)
            metric("Top artists (S/M/L)", node.topArtistsShort.count + node.topArtistsMedium.count + node.topArtistsLong.count)
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if let profile = node.profile {
            Section("Profile") {
                labelled("Display name", profile.resolvedDisplayName)
                labelled("ID", profile.id)
                if let email = profile.email { labelled("Email", email) }
                if let product = profile.product { labelled("Product", product) }
                if let country = profile.country { labelled("Country", country) }
                if let followers = profile.followers?.total { labelled("Followers", "\(followers)") }
            }
            Section("Granted scopes") {
                ForEach(node.grantedScopes, id: \.self) { scope in
                    Text(scope).font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    @ViewBuilder
    private var granularSections: some View {
        if let playing = node.currentlyPlaying?.item ?? node.playbackState?.item {
            Section("Now playing") {
                playableRow(playing)
            }
        }

        if !node.availableDevices.isEmpty {
            Section("Available devices") {
                ForEach(Array(node.availableDevices.enumerated()), id: \.offset) { _, device in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name ?? "Unnamed device")
                        Text(deviceSubtitle(device))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let queue = node.queue {
            Section("Queue") {
                if let current = queue.currentlyPlaying {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now: \(current.displayTitle)")
                        Text(current.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(queue.queue.prefix(50)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayTitle)
                        Text(item.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        navSection("Top artists — last 4 weeks", artists: node.topArtistsShort)
        navSection("Top artists — last 6 months", artists: node.topArtistsMedium)
        navSection("Top artists — all time", artists: node.topArtistsLong)
        navSection("Top tracks — last 4 weeks", tracks: node.topTracksShort)
        navSection("Top tracks — last 6 months", tracks: node.topTracksMedium)
        navSection("Top tracks — all time", tracks: node.topTracksLong)
        navSection("Followed artists", artists: node.followedArtists)
        navSection("Recently played", tracks: node.recentlyPlayed.map(\.track))
        navSection("Saved tracks", tracks: node.savedTracks.map(\.track))

        if !node.playlists.isEmpty {
            Section("Playlists") {
                ForEach(node.playlists) { playlist in
                    NavigationLink {
                        trackList(
                            title: playlist.name,
                            tracks: (node.playlistItemsByID[playlist.id] ?? []).compactMap(\.resolvedTrack)
                        )
                    } label: {
                        VStack(alignment: .leading) {
                            Text(playlist.name)
                            Text("\(playlist.tracks?.total ?? 0) tracks")
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
    private func navSection(_ title: String, tracks: [SpotifyTrack]) -> some View {
        if !tracks.isEmpty {
            Section {
                NavigationLink("\(title) (\(tracks.count))") {
                    trackList(title: title, tracks: tracks)
                }
            }
        }
    }

    @ViewBuilder
    private func navSection(_ title: String, artists: [SpotifyArtist]) -> some View {
        if !artists.isEmpty {
            Section {
                NavigationLink("\(title) (\(artists.count))") {
                    artistList(title: title, artists: artists)
                }
            }
        }
    }

    private func trackList(title: String, tracks: [SpotifyTrack]) -> some View {
        List(tracks) { trackRow($0) }
            .navigationTitle(title)
    }

    private func artistList(title: String, artists: [SpotifyArtist]) -> some View {
        List(artists) { artist in
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                if let genres = artist.genres, !genres.isEmpty {
                    Text(genres.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
    }

    private func trackRow(_ track: SpotifyTrack) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.name)
            Text(track.artistLine).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func playableRow(_ item: SpotifyPlayableItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayTitle)
            Text(item.displaySubtitle).font(.caption).foregroundStyle(.secondary)
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
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func deviceSubtitle(_ device: SpotifyPlaybackDevice) -> String {
        var parts: [String] = []
        if let type = device.type { parts.append(type) }
        if device.isActive == true { parts.append("active") }
        if device.isPrivateSession == true { parts.append("private") }
        if let volume = device.volumePercent { parts.append("\(volume)%") }
        if device.supportsVolume == false { parts.append("fixed volume") }
        return parts.isEmpty ? "Device" : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        MusicNodeView()
    }
    .environment(SpotifyMusicNode())
}
