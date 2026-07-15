import SwiftUI
import PhotosUI

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
    @Environment(NodeProgression.self) private var progression
    @Environment(\.dismiss) private var dismiss

    @State private var isSimulatingFirstInsight = false
    @State private var simulatedFirstInsight: Insight?
    @State private var activeCover: ProfileCover?
    @State private var devScheduler = UnlockNotificationScheduler()
    @AppStorage(NodeProgression.deliveryTestDeadlineKey) private var deliveryTestDeadlineRaw: Double = 0

    /// The full-screen demos launched from this surface. One cover, one enum:
    /// stacking multiple `.fullScreenCover`s on a single view makes dismissal
    /// unreliable, so both replay flows share this driver.
    private enum ProfileCover: String, Identifiable {
        case onboardingDemo, firstRunHome
        var id: String { rawValue }
    }

    // Food-visual customization: tap a node's apple to pick its emblem.
    @State private var foodStore = FoodVisualStore.shared
    @State private var editingFoodID: String?
    @State private var showFoodPicker = false
    @State private var pickedFoodItem: PhotosPickerItem?

    var body: some View {
        List {
            graphHealthSection
            journeySection
            brainSection
            if DevFlags.showProgressionDevPanel {
                progressionDevSection
            }
            foodVisualsSection
            nodesSection
            selfReportsSection
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshBrainSlices()
        }
        .photosPicker(isPresented: $showFoodPicker, selection: $pickedFoodItem, matching: .images)
        .onChange(of: pickedFoodItem) { _, item in
            guard let item, let id = editingFoodID else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    foodStore.setImage(image, for: id)
                }
                pickedFoodItem = nil
            }
        }
        // The exact first-run flow, replayed: the Spotify connect is a ghost
        // (no OAuth, template insight), and finishing lands back on home with
        // a demo-only worm name key, so the naming beat replays without
        // touching the real worm's name.
        .fullScreenCover(item: $activeCover) { cover in
            switch cover {
            case .onboardingDemo:
                OnboardingReplayDemo(onDismiss: { activeCover = nil })
            case .firstRunHome:
                // The real home, remounted from its first-run state: worm crawls
                // in, then the time-of-day picker. Uses the real worm/progression,
                // so it exercises the actual FTUE home, not the ghost-node demo.
                FirstRunHomeReplay(onDismiss: { activeCover = nil })
            }
        }
    }

    /// Reset the first-run gates so home replays from the delivery-time step, then
    /// present a fresh home. Progression drops back to base and the chosen-time
    /// flag clears, which is what makes the picker (and the worm's crawl-in) show.
    private func reloadFirstRunHome() {
        UserDefaults.standard.removeObject(forKey: NodeProgression.hasChosenDeliveryTimeKey)
        progression.reset()
        activeCover = .firstRunHome
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
                activeCover = .onboardingDemo
            } label: {
                Label("Replay first run (demo)", systemImage: "play.circle")
            }
            Button {
                Haptics.impact(.medium)
                reloadFirstRunHome()
            } label: {
                Label("Reload first time home page", systemImage: "arrow.clockwise.circle")
            }
            Button {
                Task { await readWholeProfile() }
            } label: {
                Label(profile.isSynthesizing ? "Reading…" : "Read whole profile", systemImage: "brain")
            }
            .disabled(profile.isSynthesizing)
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

    // MARK: - Journey (base + drip manager)

    /// The user-facing progression: the base foundation, then every dripped node
    /// in order, each with its status and the cosmetic it grants. Ticks once a
    /// second so the active countdown stays live.
    private var journeySection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("Phase")
                Spacer()
                Text(phaseLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(phaseColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(phaseColor.opacity(0.14), in: Capsule())
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 0) {
                    ForEach(Array(journeyRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        journeyRowView(row)
                    }
                }
            }
        } header: {
            Text("Your journey")
        } footer: {
            Text("The base comes first, no timer. After that a new node ripens every 24 hours; you can also add any source below whenever you like.")
        }
    }

    private enum StepStatus {
        case fed, ready, counting(TimeInterval), upcoming

        var isUpcoming: Bool { if case .upcoming = self { return true }; return false }
    }

    private struct JourneyRow: Identifiable {
        let entry: NodeCatalogEntry
        let status: StepStatus
        let cosmetic: CosmeticID?
        let isBase: Bool
        var id: String { entry.id }
    }

    private var journeyRows: [JourneyRow] {
        let completed = Set(progression.state.completedEntryIDs)
        var rows: [JourneyRow] = progression.baseEntries.map { entry in
            JourneyRow(entry: entry,
                       status: completed.contains(entry.id) ? .fed : .ready,
                       cosmetic: nil,
                       isBase: true)
        }
        for (index, step) in NodeCatalog.firstRunSchedule.enumerated() {
            guard let entry = NodeCatalog.entry(step.entryID) else { continue }
            rows.append(JourneyRow(entry: entry,
                                   status: dripStatus(index: index, entry: entry, completed: completed),
                                   cosmetic: step.reward.cosmetic,
                                   isBase: false))
        }
        return rows
    }

    private func dripStatus(index: Int, entry: NodeCatalogEntry, completed: Set<String>) -> StepStatus {
        if completed.contains(entry.id) { return .fed }
        guard progression.state.mode == .drip else { return .upcoming }   // base / cooldown: not yet
        if index == progression.state.cursor {
            if progression.availableUnlock?.id == entry.id { return .ready }
            if let remaining = progression.timeRemaining { return .counting(remaining) }
            return .ready
        }
        return index < progression.state.cursor ? .fed : .upcoming
    }

    private func journeyRowView(_ row: JourneyRow) -> some View {
        HStack(spacing: 12) {
            FoodAppleView(entry: row.entry, size: 40)
                .saturation(isFed(row.status) ? 1 : 0.7)
                .opacity(row.status.isUpcoming ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(row.isBase ? "base" : "drip")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let cosmetic = row.cosmetic {
                cosmeticSwatch(cosmetic)
            }
            statusBadge(row.status)
        }
        .padding(.vertical, 6)
    }

    private func statusBadge(_ status: StepStatus) -> some View {
        let (text, color): (String, Color)
        switch status {
        case .fed: (text, color) = ("fed", .green)
        case .ready: (text, color) = ("ready", .orange)
        case .counting(let remaining): (text, color) = (formattedInterval(remaining), .secondary)
        case .upcoming: (text, color) = ("soon", .secondary)
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func cosmeticSwatch(_ id: CosmeticID) -> some View {
        let earned = progression.state.earnedCosmetics.contains(id)
        return Circle()
            .fill(id.wormColor)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
            .opacity(earned ? 1 : 0.35)
            .overlay {
                if !earned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(earned ? "\(id.displayName) earned" : "\(id.displayName) locked")
    }

    private var phaseLabel: String {
        switch progression.state.mode {
        case .base: "Base"
        case .drip: "Drip"
        case .cooldown: "Cooldown"
        }
    }

    private var phaseColor: Color {
        switch progression.state.mode {
        case .base: .orange
        case .drip: .green
        case .cooldown: .secondary
        }
    }

    private func isFed(_ status: StepStatus) -> Bool {
        if case .fed = status { return true }
        return false
    }

    // MARK: - Progression Dev Panel

    private var progressionDevSection: some View {
        Section {
            metric("cursor", "\(progression.state.cursor)")
            metric("mode", progression.state.mode.rawValue)
            metric("next unlock", nextUnlockReadout)
            metric("completed", "\(progression.state.completedEntryIDs.count)")
            metric("active cosmetic", progression.state.activeCosmetic?.displayName ?? "none")
            metric("earned", earnedReadout)

            Button {
                Haptics.impact(.light)
                progression.forceUnlockNow()
            } label: {
                Label("Unlock now", systemImage: "lock.open")
            }
            Button {
                Haptics.impact(.light)
                progression.advance()
            } label: {
                Label("Advance step", systemImage: "forward")
            }
            Button {
                Haptics.impact(.light)
                progression.reset()
            } label: {
                Label("Reset progression", systemImage: "arrow.counterclockwise")
            }
            Button {
                Haptics.impact(.light)
                progression.jumpToCooldown()
            } label: {
                Label("Jump to cooldown", systemImage: "hourglass")
            }
            Button {
                startFiveSecondDigTest()
            } label: {
                Label("Set dig timer to 5 seconds", systemImage: "timer")
            }
            Button {
                Haptics.impact(.medium)
                NotificationCenter.default.post(name: .wormForceReveal, object: nil)
                dismiss()
            } label: {
                Label("Reveal today's picks now", systemImage: "sparkles")
            }
            Button {
                Haptics.impact(.light)
                Task {
                    await devScheduler.requestAuthorizationIfNeeded()
                    devScheduler.schedule(
                        at: Date().addingTimeInterval(5),
                        title: "your worm's hungry",
                        body: "test notification."
                    )
                }
            } label: {
                Label("Fire test notification (5s)", systemImage: "bell")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Fast-forward next arm")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    fastForwardButton("real", nil)
                    fastForwardButton("10s", 10.0 / 3600.0)
                    fastForwardButton("60s", 60.0 / 3600.0)
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview cosmetic")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        cosmeticButton("none", nil)
                        ForEach(CosmeticID.allCases, id: \.self) { id in
                            cosmeticButton(id.displayName, id)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Progression (dev)")
        } footer: {
            Text("Fast-forward sets the interval used by the next advance. Cosmetic preview reskins the worm on home.")
        }
    }

    private var nextUnlockReadout: String {
        if let entry = progression.availableUnlock { return entry.id }
        if let remaining = progression.timeRemaining {
            return formattedInterval(remaining)
        }
        return "none"
    }

    /// Arms the real waiting-screen countdown for five seconds. The home header
    /// and digging log read this shared deadline, so no separate demo state is
    /// needed to exercise the timer-running-out and dig-complete paths.
    private func startFiveSecondDigTest() {
        let now = Date()
        let deadline = now.addingTimeInterval(5)
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: NodeProgression.hasChosenDeliveryTimeKey)
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: "worm.digStartedAt")
        deliveryTestDeadlineRaw = deadline.timeIntervalSinceReferenceDate
        Haptics.impact(.medium)
    }

    private var earnedReadout: String {
        let names = progression.state.earnedCosmetics.map(\.displayName)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private func formattedInterval(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func fastForwardButton(_ title: String, _ hours: Double?) -> some View {
        let isSelected = progression.devIntervalOverrideHours == hours
        return Button {
            Haptics.impact(.light)
            progression.devIntervalOverrideHours = hours
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((isSelected ? Color.accentColor : Color.secondary).opacity(isSelected ? 0.22 : 0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
    }

    private func cosmeticButton(_ title: String, _ id: CosmeticID?) -> some View {
        let isSelected = progression.state.activeCosmetic == id
        return Button {
            Haptics.impact(.light)
            progression.applyCosmetic(id)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((isSelected ? Color.accentColor : Color.secondary).opacity(isSelected ? 0.22 : 0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Food visuals

    /// Every node's food — the emblem mapped onto the apple the worm eats.
    /// Tap an apple to set a custom image (persisted); long-press to reset.
    private var foodVisualsSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 16)], spacing: 18) {
                ForEach(NodeCatalog.all) { entry in
                    foodCell(entry)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Food")
        } footer: {
            Text("The emblem mapped onto each node's apple — what floats down and gets eaten. Tap to set a custom image; long-press to reset to the default.")
        }
    }

    private func foodCell(_ entry: NodeCatalogEntry) -> some View {
        Button {
            editingFoodID = entry.id
            showFoodPicker = true
        } label: {
            VStack(spacing: 6) {
                FoodAppleView(entry: entry, size: 64)
                Text(entry.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingFoodID = entry.id
                showFoodPicker = true
            } label: {
                Label("Choose image", systemImage: "photo")
            }
            if foodStore.hasCustomImage(for: entry.id) {
                Button(role: .destructive) {
                    foodStore.clearImage(for: entry.id)
                } label: {
                    Label("Reset to default", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    /// The prompt answers the user has fed directly (lock-screen, ideal-saturday,
    /// and any dripped prompts). They feed a single "prompts" brain slice, but
    /// each one shows here so the added nodes aren't invisible.
    private var selfReportsSection: some View {
        Section {
            if promptNode.answers.isEmpty {
                Text("Nothing yet — feed a prompt apple on home.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(promptNode.answers, id: \.entryID) { answer in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(answer.title)
                            .font(.subheadline.weight(.semibold))
                        Text(selfReportValue(answer))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Self-reports")
        } footer: {
            Text("What you've told the worm directly. Together these feed one \"prompts\" brain slice.")
        }
    }

    private func selfReportValue(_ answer: PromptAnswer) -> String {
        if !answer.text.isEmpty { return answer.text }
        if !answer.visionKeywords.isEmpty { return answer.visionKeywords.joined(separator: ", ") }
        return "photo saved"
    }

    private var nodesSection: some View {
        Section {
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
        } header: {
            Text("Nodes")
        } footer: {
            Text("Add any source here anytime; the daily unlock is just the nudge.")
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
        [spotifyIsPopulated, appleMusicIsPopulated, youtubeIsPopulated, contactsIsPopulated, photosIsPopulated, calendarIsPopulated, selfieIsPopulated, promptsIsPopulated]
            .filter { $0 }
            .count
    }

    private var selfieIsPopulated: Bool {
        selfie.analysis != nil
    }

    private var promptsIsPopulated: Bool {
        promptNode.hasAnswers
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

    /// Synthesize over every node's slice — the whole taste profile, not just
    /// Spotify. This is the general read; the Spotify-only path is onboarding.
    private func readWholeProfile() async {
        refreshBrainSlices()
        _ = await profile.synthesize(slices: brainInputs.slices())
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

/// The real first-run home, remounted. A fresh `WormHomeView` (so it replays the
/// forest build + worm crawl) on the real worm-name key; with the delivery-time
/// flag cleared beforehand, it lands on the time-of-day picker just like FTUE.
private struct FirstRunHomeReplay: View {
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WormHomeView(buildsForestOnEntry: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
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
            .accessibilityLabel("Close first-run home")
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .zIndex(10)
        }
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
    .environment(NodeProgression(scheduler: UnlockNotificationScheduler()))
}
