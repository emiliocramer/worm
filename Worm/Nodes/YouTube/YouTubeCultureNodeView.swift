import SwiftUI

struct YouTubeCultureNodeView: View {
    @Environment(YouTubeCultureNode.self) private var node

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
        .navigationTitle("YouTube")
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
                Label("Connect YouTube", systemImage: "play.rectangle")
            }
            .disabled(node.isAuthorizing || !node.isConfigured)
        } footer: {
            Text(node.configurationMessage ?? "Connect Google to read YouTube subscriptions, playlists, liked videos, activities, uploads, and video/channel metadata.")
        }
    }

    private var snapshotSection: some View {
        Section("Snapshot") {
            metric("Google identity", node.googleProfile == nil ? 0 : 1)
            metric("Channels", node.channels.count)
            metric("Subscriptions", node.subscriptions.count)
            metric("Channel sections", node.channelSections.count)
            metric("Activities", node.activities.count)
            metric("Playlists", node.playlists.count)
            metric("Playlist items", node.playlistItemCount)
            metric("Upload items", node.uploadItemCount)
            metric("Liked videos", node.likedVideos.count)
            metric("Enriched videos", node.enrichedVideosByID.count)
            metric("Enriched channels", node.enrichedChannelsByID.count)
            metric("Video categories", node.videoCategoriesByID.count)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            labelled("Name", node.googleProfile?.name ?? "Unknown")
            labelled("Email", node.googleProfile?.email ?? "Unknown")
            labelled("Scopes", node.grantedScopes.isEmpty ? "None" : "\(node.grantedScopes.count)")
            labelled("Redirect URI", node.callbackURIString)
            if !node.apiLimitations.isEmpty {
                NavigationLink("API limitations / misses (\(node.apiLimitations.count))") {
                    List(node.apiLimitations, id: \.self) { Text($0) }
                        .navigationTitle("YouTube Notes")
                }
            }
        }
    }

    @ViewBuilder
    private var granularSections: some View {
        if !node.channels.isEmpty {
            Section {
                NavigationLink("Channels (\(node.channels.count))") {
                    List(node.channels) { channel in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.snippet?.title ?? channel.id)
                            Text(channelSubtitle(channel)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Channels")
                }
            }
        }

        if !node.subscriptions.isEmpty {
            Section {
                NavigationLink("Subscriptions (\(node.subscriptions.count))") {
                    List(node.subscriptions) { subscription in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subscription.snippet?.title ?? subscription.id)
                            Text(subscriptionSubtitle(subscription)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Subscriptions")
                }
            }
        }

        if !node.likedVideos.isEmpty {
            videoNav("Liked Videos", node.likedVideos)
        }

        if !node.enrichedVideosByID.isEmpty {
            videoNav("Enriched Videos", Array(node.enrichedVideosByID.values).sorted { lhs, rhs in
                (lhs.snippet?.title ?? lhs.id) < (rhs.snippet?.title ?? rhs.id)
            })
        }

        if !node.playlists.isEmpty {
            Section {
                NavigationLink("Playlists (\(node.playlists.count))") {
                    List(node.playlists) { playlist in
                        NavigationLink {
                            YouTubePlaylistDetailView(
                                playlist: playlist,
                                items: node.playlistItemsByID[playlist.id] ?? [],
                                videos: node.enrichedVideosByID
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.snippet?.title ?? playlist.id)
                                Text(playlistSubtitle(playlist)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Playlists")
                }
            }
        }

        if !node.activities.isEmpty {
            Section {
                NavigationLink("Activities (\(node.activities.count))") {
                    List(node.activities) { activity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.snippet?.title ?? activity.id)
                            Text(activitySubtitle(activity)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Activities")
                }
            }
        }

        Section {
            Button("Disconnect", role: .destructive) { node.disconnect() }
        }
    }

    @ViewBuilder
    private func videoNav(_ title: String, _ videos: [YTVideo]) -> some View {
        Section {
            NavigationLink("\(title) (\(videos.count))") {
                List(videos) { video in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.snippet?.title ?? video.id)
                        Text(videoSubtitle(video)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(title)
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
                .multilineTextAlignment(.trailing)
        }
    }

    private func channelSubtitle(_ channel: YTChannel) -> String {
        var parts: [String] = []
        if let custom = channel.snippet?.customUrl { parts.append(custom) }
        if let country = channel.snippet?.country { parts.append(country) }
        if let videos = channel.statistics?.videoCount { parts.append("\(videos) videos") }
        if let subscribers = channel.statistics?.subscriberCount { parts.append("\(subscribers) subs") }
        if let topics = channel.topicDetails?.topicCategories, !topics.isEmpty {
            parts.append(topics.prefix(2).map(topicName).joined(separator: ", "))
        }
        return parts.isEmpty ? "Channel" : parts.joined(separator: " | ")
    }

    private func subscriptionSubtitle(_ subscription: YTSubscription) -> String {
        var parts: [String] = []
        if let count = subscription.contentDetails?.totalItemCount { parts.append("\(count) items") }
        if let activityType = subscription.contentDetails?.activityType { parts.append(activityType) }
        if let published = subscription.snippet?.publishedAt { parts.append(published.prefix(10).description) }
        return parts.isEmpty ? "Subscription" : parts.joined(separator: " | ")
    }

    private func playlistSubtitle(_ playlist: YTPlaylist) -> String {
        var parts: [String] = []
        if let count = node.playlistItemsByID[playlist.id]?.count ?? playlist.contentDetails?.itemCount {
            parts.append("\(count) items")
        }
        if let privacy = playlist.status?.privacyStatus { parts.append(privacy) }
        if let channel = playlist.snippet?.channelTitle { parts.append(channel) }
        if let published = playlist.snippet?.publishedAt { parts.append(published.prefix(10).description) }
        return parts.isEmpty ? "Playlist" : parts.joined(separator: " | ")
    }

    private func videoSubtitle(_ video: YTVideo) -> String {
        var parts: [String] = []
        if let channel = video.snippet?.channelTitle { parts.append(channel) }
        if let category = video.snippet?.categoryId.flatMap({ node.videoCategoriesByID[$0]?.snippet?.title }) {
            parts.append(category)
        }
        if let duration = video.contentDetails?.duration { parts.append(duration) }
        if let views = video.statistics?.viewCount { parts.append("\(views) views") }
        if let published = video.snippet?.publishedAt { parts.append(published.prefix(10).description) }
        return parts.isEmpty ? "Video" : parts.joined(separator: " | ")
    }

    private func activitySubtitle(_ activity: YTActivity) -> String {
        var parts: [String] = []
        if let type = activity.snippet?.type { parts.append(type) }
        if let channel = activity.snippet?.channelTitle { parts.append(channel) }
        if let published = activity.snippet?.publishedAt { parts.append(published.prefix(10).description) }
        return parts.isEmpty ? "Activity" : parts.joined(separator: " | ")
    }

    private func topicName(_ value: String) -> String {
        value.split(separator: "/").last.map(String.init) ?? value
    }
}

private struct YouTubePlaylistDetailView: View {
    let playlist: YTPlaylist
    let items: [YTPlaylistItem]
    let videos: [String: YTVideo]

    var body: some View {
        List {
            Section("Playlist") {
                labelled("Title", playlist.snippet?.title ?? playlist.id)
                labelled("Channel", playlist.snippet?.channelTitle ?? "Unknown")
                labelled("Items", "\(items.count)")
                if let description = playlist.snippet?.description, !description.isEmpty {
                    Text(description)
                }
            }

            Section("Items") {
                ForEach(items) { item in
                    let video = item.videoID.flatMap { videos[$0] }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video?.snippet?.title ?? item.snippet?.title ?? item.id)
                        Text(subtitle(item: item, video: video))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(playlist.snippet?.title ?? "Playlist")
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func subtitle(item: YTPlaylistItem, video: YTVideo?) -> String {
        var parts: [String] = []
        if let channel = video?.snippet?.channelTitle ?? item.snippet?.videoOwnerChannelTitle {
            parts.append(channel)
        }
        if let position = item.snippet?.position { parts.append("#\(position + 1)") }
        if let published = item.contentDetails?.videoPublishedAt ?? item.snippet?.publishedAt {
            parts.append(published.prefix(10).description)
        }
        return parts.isEmpty ? "Video" : parts.joined(separator: " | ")
    }
}

#Preview {
    NavigationStack {
        YouTubeCultureNodeView()
    }
    .environment(YouTubeCultureNode())
}
