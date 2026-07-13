import SwiftUI

/// The user's profile surface: node population, graph health, and the controls
/// needed to connect or populate sources that have not been filled yet.
struct ProfileView: View {
    @Environment(SpotifyMusicNode.self) private var spotify
    @Environment(AppleMusicNode.self) private var appleMusic
    @Environment(YouTubeCultureNode.self) private var youtube
    @Environment(ContactsNode.self) private var contacts
    @Environment(PhotosNode.self) private var photos
    @Environment(CalendarNode.self) private var calendar
    @Environment(SelfieNode.self) private var selfie
    @Environment(PromptNode.self) private var promptNode
    @Environment(TasteProfile.self) private var profile

    @State private var isSimulatingFirstInsight = false
    @State private var simulatedFirstInsight: Insight?
    @State private var isReplayingOnboarding = false

    var body: some View {
        List {
            graphHealthSection
            brainSection
            nodesSection
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshBrainSlices()
        }
        // The exact first-run flow, replayed: the Spotify connect is a ghost
        // (no OAuth, template insight), and finishing lands back on home with
        // a demo-only worm name key, so the naming beat replays without
        // touching the real worm's name.
        .fullScreenCover(isPresented: $isReplayingOnboarding) {
            OnboardingReplayDemo(onDismiss: { isReplayingOnboarding = false })
        }
    }

    // MARK: - Graph Health

    private var graphHealthSection: some View {
        Section {
            metric("Populated nodes", "\(populatedNodeCount)/\(BrainNodeID.allCases.count)")
            metric("Brain inputs active", "\(profile.populatedSliceCount)/\(BrainNodeID.allCases.count)")
            metric("Current brain", brainStatus)
            if let synthesized = profile.lastSynthesizedAt {
                metric("Last read", synthesized.formatted(date: .abbreviated, time: .shortened))
            }
        } header: {
            Text("Graph Health")
        } footer: {
            Text("Each populated node now contributes a compact brain slice. During onboarding, Spotify may be the only active slice.")
        }
    }

    private var brainSection: some View {
        Section("Brain") {
            metric("Insights", "\(profile.insights.count)")
            metric("Private read", profile.read == nil ? "Empty" : "Ready")
            NavigationLink(value: NodeRoute.profileChat) {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            Button {
                Haptics.impact(.medium)
                isReplayingOnboarding = true
            } label: {
                Label("Replay first run (demo)", systemImage: "play.circle")
            }
            Button {
                Task { await simulateFirstInsight() }
            } label: {
                Label(isSimulatingFirstInsight ? "Simulating First Insight" : "Simulate First Insight", systemImage: "sparkles")
            }
            .disabled(isSimulatingFirstInsight || !spotify.isAuthorized || profile.isSynthesizing)
            if !spotify.isAuthorized {
                Text("Connect Spotify to simulate the onboarding first insight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let simulatedFirstInsight {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest simulation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(simulatedFirstInsight.line)
                    Text(simulatedFirstInsight.evidence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            if profile.isSynthesizing {
                Label("Synthesizing", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            }
            if let error = profile.lastError {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }

    private var nodesSection: some View {
        Section("Nodes") {
            nodeRow(
                title: "Spotify",
                symbol: "music.note",
                route: .spotify,
                isAuthorized: spotify.isAuthorized,
                isBusy: spotify.isAuthorizing || spotify.isSyncing,
                isPopulated: spotifyIsPopulated,
                status: spotify.statusSummary,
                detail: spotifyDetail,
                lastSyncedAt: spotify.lastSyncedAt,
                connectOrPopulate: {
                    if spotify.isAuthorized {
                        await spotify.syncEverything()
                    } else {
                        await spotify.connect()
                    }
                },
                refresh: { await spotify.syncEverything() }
            )

            nodeRow(
                title: "Apple Music",
                symbol: "music.note.list",
                route: .appleMusic,
                isAuthorized: appleMusic.isAuthorized,
                isBusy: appleMusic.isAuthorizing || appleMusic.isSyncing,
                isPopulated: appleMusicIsPopulated,
                status: appleMusic.statusSummary,
                detail: appleMusicDetail,
                lastSyncedAt: appleMusic.lastSyncedAt,
                connectOrPopulate: {
                    if appleMusic.isAuthorized {
                        await appleMusic.syncEverything()
                    } else {
                        await appleMusic.connect()
                    }
                },
                refresh: { await appleMusic.syncEverything() }
            )

            nodeRow(
                title: "YouTube",
                symbol: "play.rectangle",
                route: .youtube,
                isAuthorized: youtube.isAuthorized,
                isBusy: youtube.isAuthorizing || youtube.isSyncing,
                isPopulated: youtubeIsPopulated,
                status: youtube.statusSummary,
                detail: youtubeDetail,
                lastSyncedAt: youtube.lastSyncedAt,
                connectOrPopulate: {
                    if youtube.isAuthorized {
                        await youtube.syncEverything()
                    } else {
                        await youtube.connect()
                    }
                },
                refresh: { await youtube.syncEverything() }
            )

            nodeRow(
                title: "Contacts",
                symbol: "person.2",
                route: .contacts,
                isAuthorized: contacts.isAuthorized,
                isBusy: contacts.isAuthorizing || contacts.isSyncing,
                isPopulated: contactsIsPopulated,
                status: contacts.statusSummary,
                detail: contactsDetail,
                lastSyncedAt: contacts.lastSyncedAt,
                connectOrPopulate: {
                    if contacts.isAuthorized {
                        await contacts.syncEverything()
                    } else {
                        await contacts.connect()
                    }
                },
                refresh: { await contacts.syncEverything() }
            )

            nodeRow(
                title: "Photos",
                symbol: "photo.on.rectangle.angled",
                route: .photos,
                isAuthorized: photos.isAuthorized,
                isBusy: photos.isAuthorizing || photos.isSyncing,
                isPopulated: photosIsPopulated,
                status: photos.statusSummary,
                detail: photosDetail,
                lastSyncedAt: photos.lastSyncedAt,
                connectOrPopulate: {
                    if photos.isAuthorized {
                        await photos.syncEverything()
                    } else {
                        await photos.connect()
                    }
                },
                refresh: { await photos.syncEverything() }
            )

            nodeRow(
                title: "Calendar",
                symbol: "calendar",
                route: .calendar,
                isAuthorized: calendar.isAuthorized,
                isBusy: calendar.isAuthorizing || calendar.isSyncing,
                isPopulated: calendarIsPopulated,
                status: calendar.statusSummary,
                detail: calendarDetail,
                lastSyncedAt: calendar.lastSyncedAt,
                connectOrPopulate: {
                    if calendar.isAuthorized {
                        await calendar.syncEverything()
                    } else {
                        await calendar.connect()
                    }
                },
                refresh: { await calendar.syncEverything() }
            )

            nodeRow(
                title: "Selfie",
                symbol: "face.smiling",
                route: .selfie,
                isAuthorized: selfie.isAuthorized,
                isBusy: selfie.isSyncing,
                isPopulated: selfieIsPopulated,
                status: selfie.statusSummary,
                detail: selfieDetail,
                lastSyncedAt: selfie.lastSyncedAt,
                connectOrPopulate: {
                    await selfie.syncEverything()
                },
                refresh: { await selfie.syncEverything() }
            )
        }
    }

    // MARK: - Rows

    private func nodeRow(
        title: String,
        symbol: String,
        route: NodeRoute,
        isAuthorized: Bool,
        isBusy: Bool,
        isPopulated: Bool,
        status: String,
        detail: String,
        lastSyncedAt: Date?,
        connectOrPopulate: @escaping () async -> Void,
        refresh: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusPill(isAuthorized: isAuthorized, isPopulated: isPopulated, isBusy: isBusy)
            }

            if let lastSyncedAt {
                Text("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if !isPopulated {
                    Button {
                        Task { await connectOrPopulate() }
                    } label: {
                        Label(isAuthorized ? "Populate" : "Connect", systemImage: "plus.circle")
                    }
                    .disabled(isBusy)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isBusy || !isAuthorized)
                }

                NavigationLink(value: route) {
                    Label("Details", systemImage: "list.bullet.rectangle")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 6)
    }

    private func statusPill(isAuthorized: Bool, isPopulated: Bool, isBusy: Bool) -> some View {
        let text = isBusy ? "Working" : isPopulated ? "Populated" : isAuthorized ? "Empty" : "Off"
        let color: Color = isBusy ? .orange : isPopulated ? .green : isAuthorized ? .yellow : .secondary

        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Derived State

    private var populatedNodeCount: Int {
        [spotifyIsPopulated, appleMusicIsPopulated, youtubeIsPopulated, contactsIsPopulated, photosIsPopulated, calendarIsPopulated, selfieIsPopulated]
            .filter { $0 }
            .count
    }

    private var selfieIsPopulated: Bool {
        selfie.analysis != nil
    }

    private var brainStatus: String {
        if profile.isSynthesizing { return "Synthesizing" }
        if !profile.insights.isEmpty { return "Ready" }
        if populatedNodeCount > 0 { return "Needs read" }
        return "Waiting for first node"
    }

    private var spotifyIsPopulated: Bool {
        spotify.profile != nil ||
            !spotify.topTracksShort.isEmpty ||
            !spotify.topArtistsShort.isEmpty ||
            !spotify.savedTracks.isEmpty ||
            !spotify.playlists.isEmpty ||
            spotify.lastSyncedAt != nil
    }

    private var appleMusicIsPopulated: Bool {
        !appleMusic.songs.isEmpty ||
            !appleMusic.albums.isEmpty ||
            !appleMusic.artists.isEmpty ||
            !appleMusic.playlists.isEmpty ||
            !appleMusic.recentlyPlayed.isEmpty ||
            !appleMusic.recommendations.isEmpty ||
            appleMusic.lastSyncedAt != nil
    }

    private var youtubeIsPopulated: Bool {
        youtube.googleProfile != nil ||
            !youtube.channels.isEmpty ||
            !youtube.subscriptions.isEmpty ||
            !youtube.playlists.isEmpty ||
            !youtube.playlistItemsByID.isEmpty ||
            !youtube.likedVideos.isEmpty ||
            !youtube.enrichedVideosByID.isEmpty ||
            youtube.lastSyncedAt != nil
    }

    private var photosIsPopulated: Bool {
        !photos.photos.isEmpty ||
            !photos.albums.isEmpty ||
            photos.lastSyncedAt != nil
    }

    private var contactsIsPopulated: Bool {
        !contacts.contacts.isEmpty ||
            !contacts.containers.isEmpty ||
            !contacts.groups.isEmpty ||
            contacts.lastSyncedAt != nil
    }

    private var calendarIsPopulated: Bool {
        !calendar.sources.isEmpty ||
            !calendar.eventCalendars.isEmpty ||
            !calendar.reminderCalendars.isEmpty ||
            !calendar.events.isEmpty ||
            !calendar.reminders.isEmpty ||
            calendar.lastSyncedAt != nil
    }

    private var spotifyDetail: String {
        "\(spotify.topTracksShort.count + spotify.topTracksMedium.count + spotify.topTracksLong.count) top tracks, \(spotify.playlists.count) playlists"
    }

    private var appleMusicDetail: String {
        "\(appleMusic.songs.count) songs, \(appleMusic.playlists.count) playlists"
    }

    private var youtubeDetail: String {
        "\(youtube.subscriptions.count) subscriptions, \(youtube.likedVideos.count) likes, \(youtube.playlistItemCount) playlist items"
    }

    private var contactsDetail: String {
        "\(contacts.contacts.count) contacts, \(contacts.groups.count) groups, \(contacts.containers.count) accounts"
    }

    private var photosDetail: String {
        "\(photos.photos.count) assets, \(photos.albums.count) albums"
    }

    private var calendarDetail: String {
        "\(calendar.events.count) events, \(calendar.reminders.count) reminders"
    }

    private var selfieDetail: String {
        selfie.analysis != nil ? "face read ready" : selfie.hasSelfie ? "selfie saved" : "no selfie"
    }

    private func refreshBrainSlices() {
        let context = brainInputs.context(read: profile.read, insights: profile.insights)
        profile.ingest(context.slices)
    }

    private var brainInputs: BrainInputSet {
        BrainInputSet(
            spotify: spotify,
            appleMusic: appleMusic,
            youtube: youtube,
            contacts: contacts,
            photos: photos,
            calendar: calendar,
            selfie: selfie,
            prompts: promptNode
        )
    }

    private func simulateFirstInsight() async {
        guard !isSimulatingFirstInsight else { return }
        isSimulatingFirstInsight = true
        defer { isSimulatingFirstInsight = false }

        simulatedFirstInsight = await FirstInsightPipeline.runSpotifyFirstInsight(
            spotify: spotify,
            profile: profile,
            selfie: selfie
        )
        refreshBrainSlices()
    }
}

private struct OnboardingReplayDemo: View {
    enum Phase { case onboarding, home }

    private static let demoWormNameKey = "worm.demo.name"

    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .onboarding

    var body: some View {
        ZStack {
            switch phase {
            case .onboarding:
                OnboardingView(demo: true) {
                    UserDefaults.standard.removeObject(forKey: Self.demoWormNameKey)
                    withAnimation(.easeInOut(duration: 0.65)) {
                        phase = .home
                    }
                }
                .transition(.opacity)
            case .home:
                NavigationStack {
                    WormHomeView(wormNameKey: Self.demoWormNameKey)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            UserDefaults.standard.removeObject(forKey: Self.demoWormNameKey)
        }
        .onDisappear {
            UserDefaults.standard.removeObject(forKey: Self.demoWormNameKey)
        }
        .overlay(alignment: .topLeading) {
            if phase == .home {
                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.76))
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close replay")
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(SpotifyMusicNode())
    .environment(AppleMusicNode())
    .environment(YouTubeCultureNode())
    .environment(ContactsNode())
    .environment(PhotosNode())
    .environment(CalendarNode())
    .environment(SelfieNode())
    .environment(TasteProfile())
}
