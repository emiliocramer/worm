import SwiftUI
import UIKit

/// Home. A quiet forest clearing, and the worm — at the size he's earned —
/// crawling in from offscreen left onto its moss bed.
/// Food drifts down for nodes that can be added; in dev mode populated nodes
/// can still appear as mock morsels so the node-creation flow stays testable.
/// Copy stays out of the way: the screen itself says "feed worm, worm finds music."
struct WormHomeView: View {
    @Environment(SpotifyMusicNode.self) private var spotify
    @Environment(AppleMusicNode.self) private var appleMusic
    @Environment(YouTubeCultureNode.self) private var youtube
    @Environment(PhotosNode.self) private var photos
    @Environment(ContactsNode.self) private var contacts
    @Environment(CalendarNode.self) private var calendar
    @Environment(PromptNode.self) private var promptNode
    @Environment(TasteProfile.self) private var profile
    @Environment(NodeProgression.self) private var progression
    @AppStorage private var wormName: String
    @AppStorage("worm.askedNotificationPermission") private var askedNotificationPermission = false
    @FocusState private var nameFieldFocused: Bool

    /// Entrance clock: nil until this appearance's crawl begins.
    @State private var entranceStart: Double?
    /// The gulp, in the exact grammar the onboarding taught.
    @State private var gulpStart: Double?
    @State private var fromSize = OnboardingWormSize.seed
    @State private var toSize = OnboardingWormSize.seed
    /// The one morsel currently on screen (restraint: never a rain of icons).
    @State private var morsel: FeedMorsel?
    @State private var morselPhase = MorselPhase.offscreen
    @State private var morselFlight: CGFloat = 0
    /// Where the flying morsel launches from. Nil = the drip hover point; set to a
    /// tree slot while a base apple is being eaten.
    @State private var morselOrigin: CGPoint?
    // MARK: Base phase (first-run foundation, no countdown)
    /// The foundation apples that have popped into the trees so far — populated
    /// one at a time on entry so they arrive staggered, not all at once.
    @State private var revealedBaseIDs: Set<String> = []
    /// The base apple currently flying into the worm — hidden from the tree layer
    /// so it doesn't double with the flying morsel.
    @State private var consumingBaseID: String?
    /// Where a base prompt apple sat, remembered across its capture sheet.
    @State private var pendingBaseOrigin: CGPoint?
    /// One quiet line under the worm while he digests a new node.
    @State private var digestCaption: String?
    /// The prompt-kind entry currently being captured in the sheet, if any.
    @State private var capturingEntry: NodeCatalogEntry?
    @State private var namingStep: NamingStep = .intro
    @State private var namingHeroVisible = false
    @State private var namingButtonVisible = false
    @State private var namingCompleted = false
    @State private var nameTagVisible = false
    @State private var namingHandoffVisible = false
    @State private var namingHandoffButtonVisible = false
    @State private var draftWormName = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var fixedViewportSize: CGSize = .zero
    @State private var wormWiggles: [Worm.Wiggle] = []
    @State private var lastWormTapAt = -Double.infinity
    @State private var forestBuildProgress: CGFloat
    @State private var hasCompletedForestBuild = false
    @State private var homeControlsVisible: Bool
    @State private var forestBuildTask: Task<Void, Never>?

    private enum MorselPhase { case offscreen, hovering, fed, gone }
    private enum NamingStep { case intro, entry }

    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    private let ink = Color.black

    private var wormColor: Color { progression.state.activeCosmetic?.wormColor ?? ink }
    private var wormEyeColor: Color { progression.state.activeCosmetic?.eyeColor ?? paper }
    private let wormEntranceDelay = 0.35
    private let wormEntranceDuration = 2.9
    private let wormEntranceSettleDuration = 0.7
    private let forestBuildDuration = 1.9
    private let buildsForestOnEntry: Bool
    private let forestBuildDelay: Double

    init(
        wormNameKey: String = "worm.name",
        buildsForestOnEntry: Bool = false,
        forestBuildDelay: Double = 0
    ) {
        self.buildsForestOnEntry = buildsForestOnEntry
        self.forestBuildDelay = forestBuildDelay
        _wormName = AppStorage(wrappedValue: "", wormNameKey)
        _forestBuildProgress = State(initialValue: buildsForestOnEntry ? 0 : 1)
        _homeControlsVisible = State(initialValue: !buildsForestOnEntry)
    }

    var body: some View {
        GeometryReader { geo in
            let viewport = stableViewportSize(for: geo.size)
            let W = viewport.width, H = viewport.height
            let restCenter = CGPoint(x: W / 2, y: H * 0.78)
            let feedPoint = CGPoint(
                x: restCenter.x + fromSize.length / 2 - fromSize.thickness * 0.15,
                y: restCenter.y - fromSize.thickness * 0.42
            )
            let hoverPoint = CGPoint(x: W / 2, y: H * 0.42)

            ZStack(alignment: .topLeading) {
                // Forest art starts transparent. Keep the splash's paper under
                // it so this handoff can never expose the window backing color.
                paper.ignoresSafeArea()

                ForestHomeBackdrop(buildProgress: forestBuildProgress)
                    .ignoresSafeArea()

                ZStack {
                    HomeWorm(
                        entranceStart: entranceStart,
                        gulpStart: gulpStart,
                        restCenter: restCenter,
                        fromSize: fromSize,
                        toSize: toSize,
                        entranceDuration: wormEntranceDuration,
                        settleDuration: wormEntranceSettleDuration,
                        color: wormColor,
                        eyeColor: wormEyeColor,
                        wiggles: wormWiggles,
                        onTap: reactToWormTap
                    )
                    .ignoresSafeArea(.keyboard, edges: .bottom)

                    ForestHomeForeground(buildProgress: forestBuildProgress)
                        .ignoresSafeArea()

                    if nameTagVisible,
                       let displayName = wormDisplayName,
                       !isNamingFlowActive,
                       !namingHandoffVisible {
                        HomeWormNameTag(
                            name: displayName,
                            entranceStart: entranceStart,
                            gulpStart: gulpStart,
                            restCenter: restCenter,
                            fromSize: fromSize,
                            toSize: toSize,
                            entranceDuration: wormEntranceDuration,
                            settleDuration: wormEntranceSettleDuration,
                            viewport: viewport,
                            ink: ink,
                            paper: paper
                        )
                        .transition(.nameTagPop)
                        .zIndex(1)
                        .allowsHitTesting(false)
                    }

                    if isNamingFlowActive, namingHeroVisible {
                        namingHero(height: H)
                            .transition(.opacity)
                            .zIndex(2)
                    }

                    if namingHandoffVisible, let displayName = wormDisplayName {
                        namingHandoff(name: displayName, height: H)
                            .transition(.opacity)
                            .zIndex(2)
                    }

                    // Base phase: a few prominent apples scattered in the trees,
                    // fed in any order, no countdown until the last one lands.
                    if progression.isBasePhase, !isNamingFlowActive {
                        ForEach(progression.pendingBaseEntries) { entry in
                            if entry.id != consumingBaseID, revealedBaseIDs.contains(entry.id) {
                                let slot = baseApplePosition(for: entry, in: viewport)
                                VStack(spacing: 8) {
                                    FeedMorselView(entry: entry, ink: ink, paper: paper)
                                        .modifier(AttentionPulse(active: true))
                                    Text(entry.title)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(ink.opacity(0.42))
                                        .frame(maxWidth: 120)
                                        .multilineTextAlignment(.center)
                                }
                                .position(slot)
                                .modifier(HoverBob(active: true))
                                .onTapGesture { tapBaseApple(entry, at: slot) }
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                            }
                        }
                    }

                    if !isNamingFlowActive, let morsel, morselPhase == .hovering || morselPhase == .fed {
                        let fed = morselPhase == .fed
                        let flight = fed ? morselFlight : 0
                        let bite = Self.smoothstep(0.68, 1, Double(flight))
                        VStack(spacing: 8) {
                            FeedMorselView(entry: morsel.entry, ink: ink, paper: paper)
                                .modifier(AttentionPulse(active: morselPhase == .hovering))
                            Text(morsel.entry.title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(ink.opacity(0.4))
                                .opacity(fed ? 0 : 1)
                        }
                        .scaleEffect(1 - 0.9 * CGFloat(bite))
                        .rotationEffect(.degrees(-6 + 28 * Double(flight)))
                        .opacity(1 - 0.18 * CGFloat(bite))
                        .position(Self.morselPosition(from: morselOrigin ?? hoverPoint, to: feedPoint, progress: flight))
                        .modifier(HoverBob(active: morselPhase == .hovering))
                        .animation(.interpolatingSpring(mass: 0.55, stiffness: 245, damping: 20, initialVelocity: 1.0), value: morselPhase)
                        .animation(.timingCurve(0.18, 0.84, 0.18, 1, duration: 0.64), value: morselFlight)
                        .onTapGesture { feed(morsel) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let digestCaption {
                        Text(digestCaption)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(ink.opacity(0.4))
                            .position(x: W / 2, y: restCenter.y + 56)
                            .transition(.opacity)
                    }
                }
                .frame(width: W, height: H, alignment: .topLeading)
            }
            .onAppear { captureStableViewport(geo.size) }
            .onChange(of: geo.size) { _, newSize in
                captureStableViewport(newSize)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .top) {
            if !isNamingFlowActive, !namingHandoffVisible, homeControlsVisible {
                if progression.isBasePhase {
                    // Sit where the countdown's "daily food ready" line sits, so
                    // the base and drip headers occupy the same spot.
                    baseEncouragement
                        .padding(.top, 8)
                        .offset(y: 100)
                } else {
                    CountdownHeaderView(
                        progression: progression,
                        ink: ink,
                        paper: paper,
                        onOpen: {
                            Haptics.impact(.medium)
                            Task { await presentNextMorsel() }
                        }
                    )
                    .padding(.top, 8)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if homeControlsVisible, !isNamingFlowActive, !namingHandoffVisible {
                NavigationLink(value: NodeRoute.profile) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.76))
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
        }
        .overlay(alignment: .bottom) {
            if namingHandoffVisible, namingHandoffButtonVisible {
                namingHandoffButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isNamingFlowActive, namingButtonVisible {
                namingButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, namingButtonBottomPadding)
                    .transition(.bottomFlip)
                    .animation(.spring(response: 0.55, dampingFraction: 0.78), value: namingButtonVisible)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification), perform: updateKeyboardHeight)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification), perform: updateKeyboardHeight)
        .onAppear(perform: beginHomePresentation)
        .onDisappear {
            forestBuildTask?.cancel()
            forestBuildTask = nil
            entranceStart = nil
            nameFieldFocused = false
            keyboardHeight = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .wormUnlockTapped)) { _ in
            Task { await presentNextMorsel() }
        }
        .fullScreenCover(item: $capturingEntry) { entry in
            PromptCaptureView(
                entry: entry,
                ink: ink,
                paper: paper,
                onCancel: { cancelCapture() },
                onSubmit: { value in submitCapture(entry: entry, value: value) }
            )
        }
    }

    @ViewBuilder
    private func namingHero(height H: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: H * 0.20)

            ZStack {
                if namingStep == .intro {
                    Text("i think its time to give your worm a name")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 36)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    VStack(spacing: 20) {
                        Text("a name fit for a worm")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.88))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .minimumScaleFactor(0.78)

                        TextField("", text: $draftWormName)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFieldFocused)
                            .onSubmit { submitWormName() }
                            .padding(.vertical, 8)
                            .frame(maxWidth: 280)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(ink.opacity(nameFieldFocused ? 0.9 : 0.45))
                                    .frame(height: 2)
                            }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.42), value: namingStep)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .allowsHitTesting(namingStep == .entry)
    }

    private var namingButton: some View {
        let disabled = namingStep == .entry && !canSubmitName
        return Button(action: handleNamingButtonTap) {
            Text(namingStep == .intro ? "lets do it" : "submit")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(disabled ? ink.opacity(0.42) : paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(disabled ? Color.gray.opacity(0.26) : ink, in: Capsule())
        }
        .disabled(disabled)
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private func namingHandoff(name: String, height: CGFloat) -> some View {
        VStack(spacing: 12) {
            Spacer().frame(height: height * 0.25)

            Text("\(name).")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.9))

            Text("you can always change it later")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.5))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .allowsHitTesting(false)
    }

    private var namingHandoffButton: some View {
        Button(action: completeNamingHandoff) {
            Text("continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private var namingButtonBottomPadding: CGFloat {
        keyboardHeight > 0 ? keyboardHeight + 4 : 24
    }

    // MARK: - Base phase

    /// The stacked line shown up top during the base phase, in place of the
    /// countdown. Big and inviting: build the worm a foundation before the drip.
    private var baseEncouragement: some View {
        let remaining = progression.pendingBaseEntries.count
        return VStack(spacing: 4) {
            Text("FEED HIM")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(ink.opacity(0.85))
            Text("A BASE")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(ink.opacity(0.86))
            Text(baseSubtitle(remaining: remaining))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.45))
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
    }

    private func baseSubtitle(remaining: Int) -> String {
        switch remaining {
        case 1: "one more to go"
        case 2: "two more to go"
        default: "everything he eats makes him sharper"
        }
    }

    /// A fixed tree slot per base entry, keyed off its position in the base set so
    /// apples never reshuffle as siblings get eaten. Scattered heights, "in the
    /// trees": upper-left canopy, upper-right canopy, lower-center.
    private func baseApplePosition(for entry: NodeCatalogEntry, in viewport: CGSize) -> CGPoint {
        let slots: [(CGFloat, CGFloat)] = [(0.23, 0.50), (0.77, 0.44), (0.50, 0.60)]
        let index = progression.baseEntries.firstIndex(of: entry) ?? 0
        let (fx, fy) = slots[index % slots.count]
        return CGPoint(x: viewport.width * fx, y: viewport.height * fy)
    }

    private func stableViewportSize(for proposed: CGSize) -> CGSize {
        fixedViewportSize == .zero ? proposed : fixedViewportSize
    }

    private func captureStableViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard keyboardHeight == 0, !nameFieldFocused else { return }
        fixedViewportSize = size
    }

    // MARK: - Entrance

    /// The scene only resolves out of the landing transition. Once visible,
    /// pushed destinations return to the existing habitat and replay only the
    /// mascot's familiar crawl.
    private func beginHomePresentation() {
        forestBuildTask?.cancel()

        guard buildsForestOnEntry, !hasCompletedForestBuild else {
            forestBuildProgress = 1
            homeControlsVisible = true
            beginEntrance()
            return
        }

        hasCompletedForestBuild = true
        forestBuildProgress = 0
        homeControlsVisible = false
        entranceStart = nil

        forestBuildTask = Task {
            // Guarantee at least one settled paper frame between the landing
            // disappearing and the first scene pixel changing.
            try? await Task.sleep(for: .seconds(max(0.10, forestBuildDelay)))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: forestBuildDuration)) {
                    forestBuildProgress = 1
                }
            }
            try? await Task.sleep(for: .seconds(forestBuildDuration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.28)) {
                    homeControlsVisible = true
                }
                beginEntrance()
                forestBuildTask = nil
            }
        }
    }

    // He crawls in every time you come home, but waits for the initial forest.

    private func beginEntrance() {
        let size = earnedSize
        fromSize = size
        toSize = size
        gulpStart = nil
        morselPhase = .offscreen
        morselFlight = 0
        morsel = nil
        morselOrigin = nil
        revealedBaseIDs = []
        consumingBaseID = nil
        digestCaption = nil
        wormWiggles = []
        nameTagVisible = false
        resetNamingFlowIfNeeded()

        Task {
            try? await Task.sleep(for: .seconds(wormEntranceDelay))
            await MainActor.run {
                entranceStart = Date().timeIntervalSinceReferenceDate
                Haptics.impact(.medium)
            }
            try? await Task.sleep(for: .seconds(1.45))
            await MainActor.run { Haptics.impact(.light, intensity: 0.6) }
            try? await Task.sleep(for: .seconds(max(0, wormEntranceDuration - 1.45)))

            try? await Task.sleep(for: .seconds(wormEntranceSettleDuration))

            if isNamingFlowActive {
                await MainActor.run {
                    guard isNamingFlowActive else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        namingHeroVisible = true
                    }
                }
                await revealNamingButton()
            } else {
                await revealNameTagIfReady()
                await revealFoodForCurrentPhase()
            }
        }
    }

    /// After the worm has settled (and been named), reveal whatever the current
    /// phase offers: the scattered base apples, or the single drip morsel.
    private func revealFoodForCurrentPhase() async {
        if progression.isBasePhase {
            // Pop the apples into the trees one at a time so they arrive as a
            // little scatter, not a single simultaneous appearance.
            for entry in progression.pendingBaseEntries {
                await MainActor.run {
                    guard progression.isBasePhase else { return }
                    withAnimation(.spring(response: 0.62, dampingFraction: 0.7)) {
                        _ = revealedBaseIDs.insert(entry.id)
                    }
                    Haptics.impact(.light, intensity: 0.4)
                }
                try? await Task.sleep(for: .seconds(0.45))
            }
        } else {
            await presentNextMorsel()
        }
    }

    // MARK: - Worm touch

    private func reactToWormTap(origin: Double) {
        let now = Date().timeIntervalSinceReferenceDate
        wormWiggles.removeAll { now - $0.startedAt > 0.72 }

        let rapidTapCount = wormWiggles.filter { now - $0.startedAt < 0.28 }.count
        let strength = min(1.35, 0.78 + Double(rapidTapCount) * 0.14)

        // Repeatedly drumming one spot feeds the same ripple rather than piling
        // up unlimited identical waves.
        if let index = wormWiggles.indices.last,
           now - wormWiggles[index].startedAt < 0.075,
           abs(wormWiggles[index].origin - origin) < 0.12 {
            let previous = wormWiggles.remove(at: index)
            wormWiggles.append(.init(
                startedAt: now,
                origin: origin,
                strength: min(1.55, previous.strength + 0.26)
            ))
        } else {
            wormWiggles.append(.init(startedAt: now, origin: origin, strength: strength))
            if wormWiggles.count > 6 { wormWiggles.removeFirst(wormWiggles.count - 6) }
        }

        // Hardware blurs very fast impacts together. This tiny throttle keeps a
        // barrage crisp, while the rising intensity rewards the rhythm.
        if now - lastWormTapAt > 0.045 {
            Haptics.tick(intensity: min(0.86, 0.42 + Double(rapidTapCount) * 0.09))
            lastWormTapAt = now
        }
    }

    /// The worm's earned size: every populated node stretches him. Same body
    /// grammar as onboarding (seed 15pt; selfie+Spotify landed at ~118pt).
    private var earnedSize: OnboardingWormSize {
        let populated = profile.populatedSliceCount
        let completed = progression.state.completedEntryIDs.count
        return OnboardingWormSize(
            length: 15 + CGFloat(populated) * 34 + CGFloat(completed) * 22 + CGFloat(min(profile.insights.count, 6)) * 5,
            thickness: 16 + CGFloat(min(populated + completed, 12))
        )
    }

    // MARK: - Morsels (food drifts in for whatever he hasn't eaten yet)

    private var nextMorsel: FeedMorsel? {
        progression.availableUnlock.map(FeedMorsel.init)
    }

    private func presentNextMorsel() async {
        guard hasWormName, morselPhase == .offscreen, let next = nextMorsel else { return }
        await MainActor.run {
            morsel = next
            morselFlight = 0
            withAnimation(.spring(response: 1.1, dampingFraction: 0.8)) {
                morselPhase = .hovering
            }
        }
        // A light haptic nudge after a beat, drawing attention to the waiting
        // morsel. The apple's own grow+glow pulse carries the "tap me" signal;
        // no copy needed.
        try? await Task.sleep(for: .seconds(2.6))
        await MainActor.run {
            guard morselPhase == .hovering else { return }
            Haptics.impact(.light, intensity: 0.4)
        }
    }

    // MARK: - Naming

    private var hasWormName: Bool {
        !wormName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var wormDisplayName: String? {
        let trimmed = wormName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var isNamingFlowActive: Bool {
        !hasWormName && !namingCompleted
    }

    private var canSubmitName: Bool {
        draftWormName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private func resetNamingFlowIfNeeded() {
        guard !hasWormName else {
            namingCompleted = true
            namingHeroVisible = false
            namingButtonVisible = false
            nameTagVisible = false
            namingHandoffVisible = false
            namingHandoffButtonVisible = false
            nameFieldFocused = false
            return
        }
        namingCompleted = false
        namingStep = .intro
        namingHeroVisible = false
        namingButtonVisible = false
        nameTagVisible = false
        namingHandoffVisible = false
        namingHandoffButtonVisible = false
        draftWormName = ""
        nameFieldFocused = false
    }

    private func revealNameTagIfReady() async {
        await MainActor.run {
            guard wormDisplayName != nil else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                nameTagVisible = true
            }
        }
    }

    private func revealNamingButton() async {
        try? await Task.sleep(for: .seconds(2.0))
        await MainActor.run {
            guard isNamingFlowActive, namingStep == .intro else { return }
            Haptics.impact(.light, intensity: 0.45)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                namingButtonVisible = true
            }
        }
    }

    private func handleNamingButtonTap() {
        switch namingStep {
        case .intro:
            Haptics.impact(.medium)
            withAnimation(.easeInOut(duration: 0.42)) {
                namingStep = .entry
            }
            Task {
                // Let the input finish entering before UIKit begins its keyboard
                // presentation; overlapping those two animations drops frames.
                try? await Task.sleep(for: .seconds(0.62))
                await MainActor.run {
                    guard isNamingFlowActive, namingStep == .entry else { return }
                    nameFieldFocused = true
                }
            }
        case .entry:
            submitWormName()
        }
    }

    private func submitWormName() {
        let trimmed = draftWormName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        Haptics.success()
        withAnimation(.easeOut(duration: 0.3)) {
            nameFieldFocused = false
            namingButtonVisible = false
            namingHeroVisible = false
        }

        Task {
            // Let the keyboard and naming prompt finish leaving before the
            // confirmation becomes the next authored beat.
            try? await Task.sleep(for: .seconds(0.55))
            await MainActor.run {
                wormName = trimmed
                namingCompleted = true
                homeControlsVisible = false
                withAnimation(.easeInOut(duration: 0.65)) {
                    namingHandoffVisible = true
                }
            }

            // Match onboarding: let the copy land, then offer the action as a
            // separate beat instead of animating everything at once.
            try? await Task.sleep(for: .seconds(1.7))
            await MainActor.run {
                guard namingHandoffVisible else { return }
                Haptics.impact(.light, intensity: 0.45)
                withAnimation(.easeIn(duration: 0.4)) {
                    namingHandoffButtonVisible = true
                }
            }
        }
    }

    private func completeNamingHandoff() {
        Haptics.impact(.medium)
        withAnimation(.easeOut(duration: 0.35)) {
            namingHandoffButtonVisible = false
            namingHandoffVisible = false
        }

        Task {
            // The name tag gets its own landing, after the confirmation has
            // completely cleared. Food and navigation wait another full beat.
            try? await Task.sleep(for: .seconds(0.6))
            await revealNameTagIfReady()
            try? await Task.sleep(for: .seconds(1.0))
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.4)) {
                    homeControlsVisible = true
                }
            }
            await revealFoodForCurrentPhase()
        }
    }

    private func updateKeyboardHeight(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let screenHeight = UIScreen.main.bounds.height
        let nextHeight: CGFloat
        if notification.name == UIResponder.keyboardWillHideNotification {
            nextHeight = 0
        } else {
            nextHeight = max(0, screenHeight - endFrame.minY)
        }

        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = nextHeight
        }
    }

    // MARK: - Feeding

    private func feed(_ morsel: FeedMorsel) {
        guard morselPhase == .hovering else { return }
        let entry = morsel.entry
        Haptics.impact(.medium)

        switch entry.captureKind {
        case .source:
            // A source node: gulp now, then go connect it.
            gulpAndGrow()
            Task {
                await settleGrow()
                await connectSource(entry)
            }
        case .photo, .text, .choice:
            // A self-report prompt: collect the answer first, swallow it after.
            capturingEntry = entry
        }
    }

    // MARK: - Base feeding

    /// Tap on a base apple sitting in the trees: connect a source right away, or
    /// collect a prompt answer first. Either way it flies from its slot into the
    /// worm on success.
    private func tapBaseApple(_ entry: NodeCatalogEntry, at slot: CGPoint) {
        guard consumingBaseID == nil, capturingEntry == nil else { return }
        Haptics.impact(.medium)
        switch entry.captureKind {
        case .source:
            beginBaseConsume(entry, from: slot)
            Task {
                await settleGrow()
                await connectBaseSource(entry)
            }
        case .photo, .text, .choice:
            pendingBaseOrigin = slot
            capturingEntry = entry
        }
    }

    /// Hand the tapped tree apple over to the flying-morsel machinery, launching
    /// from its slot so the handoff is seamless.
    private func beginBaseConsume(_ entry: NodeCatalogEntry, from slot: CGPoint) {
        morsel = FeedMorsel(entry: entry)
        morselOrigin = slot
        consumingBaseID = entry.id
        gulpAndGrow()
    }

    private func connectBaseSource(_ entry: NodeCatalogEntry) async {
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.5)) { digestCaption = "eating \(entry.title)..." }
        }
        if await connectNode(for: entry.sourceRoute) {
            await MainActor.run {
                Haptics.success()
                withAnimation(.easeOut(duration: 0.6)) { digestCaption = nil }
                finishBaseUnlock(entry)
            }
        } else {
            // Denied or failed: the apple returns to its tree slot, uneaten.
            await MainActor.run {
                fromSize = earnedSize
                toSize = earnedSize
                gulpStart = nil
                withAnimation(.easeInOut(duration: 0.5)) { digestCaption = "maybe later." }
            }
            try? await Task.sleep(for: .seconds(1.8))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.6)) { digestCaption = nil }
                morsel = nil
                morselPhase = .offscreen
                morselOrigin = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    consumingBaseID = nil   // apple reappears in its slot
                }
            }
        }
    }

    /// A base apple landed: record it. If it was the last of the base, cross into
    /// the drip — arm the first 24h countdown and ask for notifications.
    private func finishBaseUnlock(_ entry: NodeCatalogEntry) {
        progression.claim(entry: entry)
        let baseComplete = progression.pendingBaseEntries.isEmpty

        // Clear the flying morsel; any remaining base apples stay in the trees.
        morsel = nil
        morselPhase = .offscreen
        morselOrigin = nil
        pendingBaseOrigin = nil
        withAnimation(.easeOut(duration: 0.3)) { consumingBaseID = nil }

        guard baseComplete else { return }

        // Base done: flip to the drip. advance() arms the first countdown, so the
        // header (hidden all through the base) now slides in with a live clock.
        revealedBaseIDs = []
        progression.advance()
        if !askedNotificationPermission {
            askedNotificationPermission = true
            Task { await progression.requestNotificationPermission() }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await presentNextMorsel()   // no-op while the fresh countdown runs
        }
    }

    /// The bite: the morsel flies into the worm's mouth.
    private func gulpAndGrow() {
        morselFlight = 0
        morselPhase = .fed
        withAnimation(.timingCurve(0.18, 0.84, 0.18, 1, duration: 0.64)) {
            morselFlight = 1
        }
    }

    /// After the bite lands, the worm swallows and grows a notch.
    private func settleGrow() async {
        try? await Task.sleep(for: .seconds(0.66))
        await MainActor.run {
            let grown = OnboardingWormSize(
                length: earnedSize.length + 34,
                thickness: earnedSize.thickness + 1
            )
            fromSize = earnedSize
            toSize = grown
            gulpStart = Date().timeIntervalSinceReferenceDate
            Haptics.impact(.heavy)
            withAnimation(.easeOut(duration: 0.18)) { morselPhase = .gone }
        }
    }

    // MARK: - Prompt capture

    /// User backed out of the sheet: the morsel returns to hover, uneaten and
    /// un-advanced.
    private func cancelCapture() {
        capturingEntry = nil
        // In the base phase the apple never left its tree slot, so there's nothing
        // to send back to hover — it's still sitting there.
        if progression.isBasePhase {
            pendingBaseOrigin = nil
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            morselPhase = .hovering
        }
    }

    /// User answered the prompt: record it, then run the gulp + reward.
    private func submitCapture(entry: NodeCatalogEntry, value: PromptCaptureValue) {
        capturingEntry = nil
        switch value {
        case .text(let str):
            promptNode.record(entryID: entry.id, title: entry.title, answer: str)
        case .photo:
            // v1: vision keywords TODO, a real on-device read comes later.
            promptNode.recordPhoto(entryID: entry.id, title: entry.title, visionKeywords: [])
        }
        if progression.isBasePhase {
            let origin = pendingBaseOrigin ?? CGPoint(x: fixedViewportSize.width / 2,
                                                      y: fixedViewportSize.height * 0.4)
            beginBaseConsume(entry, from: origin)
            Task {
                await settleGrow()
                await MainActor.run { finishBaseUnlock(entry) }
            }
        } else {
            gulpAndGrow()
            Task {
                await settleGrow()
                await MainActor.run { finishUnlock(entry) }
            }
        }
    }

    // MARK: - Source connect

    private func connectSource(_ entry: NodeCatalogEntry) async {
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.5)) { digestCaption = "eating \(entry.title)..." }
        }
        if await connectNode(for: entry.sourceRoute) {
            await MainActor.run {
                Haptics.success()
                withAnimation(.easeOut(duration: 0.6)) { digestCaption = nil }
                finishUnlock(entry)
            }
        } else {
            // Denied or failed: he spits nothing back out, the size settles
            // where it was, and the ask returns another day. No claim, no advance.
            await MainActor.run {
                fromSize = earnedSize
                toSize = earnedSize
                gulpStart = nil
                withAnimation(.easeInOut(duration: 0.5)) { digestCaption = "maybe later." }
            }
            try? await Task.sleep(for: .seconds(1.8))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.6)) { digestCaption = nil }
            }
            // No claim, no advance: the unlock is still available. Reset the
            // morsel phase (it's stuck at .gone) so the header pill tap, the
            // notification, or this re-present all work again for a retry.
            await MainActor.run {
                morsel = nil
                morselPhase = .offscreen
            }
            await presentNextMorsel()
        }
    }

    /// Drive the source node matching this route through connect + sync. Returns
    /// whether it ended up authorized.
    private func connectNode(for route: NodeRoute?) async -> Bool {
        switch route {
        case .appleMusic:
            await appleMusic.connect()
            guard appleMusic.isAuthorized else { return false }
            await appleMusic.syncEverything()
            return true
        case .youtube:
            await youtube.connect()
            guard youtube.isAuthorized else { return false }
            await youtube.syncEverything()
            return true
        case .photos:
            await photos.connect()
            guard photos.isAuthorized else { return false }
            await photos.syncEverything()
            return true
        case .contacts:
            await contacts.connect()
            guard contacts.isAuthorized else { return false }
            await contacts.syncEverything()
            return true
        case .calendar:
            await calendar.connect()
            guard calendar.isAuthorized else { return false }
            await calendar.syncEverything()
            return true
        case .spotify:
            await spotify.connect()
            guard spotify.isAuthorized else { return false }
            await spotify.syncEverything()
            return true
        default:
            return false
        }
    }

    // MARK: - Reward

    /// A successful feed: record the reward, arm the next countdown.
    private func finishUnlock(_ entry: NodeCatalogEntry) {
        let reward = progression.claim(entry: entry)   // records completion; sets activeCosmetic if any
        if let cosmetic = reward.cosmetic {
            withAnimation(.easeIn(duration: 0.4)) { digestCaption = "unlocked: \(cosmetic.displayName)." }
        }
        progression.advance()   // arms the next countdown; header returns to locked

        // The first countdown just armed: ask for notification permission once,
        // contextually, on the REAL scheduler (never at launch).
        if !askedNotificationPermission {
            askedNotificationPermission = true
            Task { await progression.requestNotificationPermission() }
        }

        // The morsel finished its .hovering -> .fed -> .gone arc. Reset it so a
        // fresh unlock (short intervals / cooldown) can be presented this session
        // without waiting for a home re-appear.
        morsel = nil
        morselPhase = .offscreen

        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.6)) { digestCaption = nil }
            }
            // advance() re-armed a future countdown, so availableUnlock is
            // normally nil and this is a harmless no-op; call it in case a next
            // unlock is already available.
            await presentNextMorsel()
        }
    }

    private static func morselPosition(from start: CGPoint, to end: CGPoint, progress raw: CGFloat) -> CGPoint {
        let t = min(max(raw, 0), 1)
        let control = CGPoint(
            x: (start.x + end.x) / 2 + 24,
            y: min(start.y, end.y) - 76
        )
        let inv = 1 - t
        return CGPoint(
            x: inv * inv * start.x + 2 * inv * t * control.x + t * t * end.x,
            y: inv * inv * start.y + 2 * inv * t * control.y + t * t * end.y
        )
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - The worm at home

/// The home worm: SnackingWorm's body and gulp grammar, plus an entrance that
/// crawls in from offscreen left with gather-and-lunge inchworm pacing.
private struct HomeWorm: View {
    var entranceStart: Double?
    var gulpStart: Double?
    var restCenter: CGPoint
    var fromSize: OnboardingWormSize
    var toSize: OnboardingWormSize
    var entranceDuration: Double
    var settleDuration: Double
    var color: Color
    var eyeColor: Color
    var wiggles: [Worm.Wiggle]
    var onTap: (Double) -> Void

    private static let worm = Worm.snacking

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in
                var w = Self.worm
                w.color = color
                w.eyeColor = eyeColor

                var center = restCenter
                var length = fromSize.length
                var thickness = fromSize.thickness
                var centerline: [CGPoint]
                var gaitWeights: [Double]?

                // Entrance: fully offscreen left until the clock starts, then
                // head/tail stride motion pulls him into the resting spot.
                let crawlDuration = entranceDuration
                var isEntering = true
                if let start = entranceStart {
                    let dt = max(0, t - start)
                    if dt < crawlDuration {
                        centerline = Self.inchwormEntranceCenterline(
                            restCenter: restCenter,
                            length: length,
                            thickness: thickness,
                            elapsed: dt,
                            duration: crawlDuration,
                            strides: 6
                        )
                        gaitWeights = Array(repeating: 0.22, count: centerline.count)
                    } else {
                        isEntering = false
                        let settle = dt - crawlDuration
                        if settle > 0, settle < settleDuration {
                            center.x += CGFloat(sin(settle / settleDuration * .pi) * exp(-settle * 3.0)) * 7
                        }
                        centerline = Worm.straightCenterline(center: center, length: length)
                    }
                } else {
                    centerline = Self.hiddenCenterline(restCenter: restCenter, length: length, thickness: thickness)
                    gaitWeights = Array(repeating: 0.05, count: centerline.count)
                }

                if !isEntering, let g = gulpStart {
                    let dt = max(0, t - g)
                    let pop = dt < 0.16 ? dt / 0.16 : exp(-(dt - 0.16) * 2.4)
                    let sm = min(1, dt / 0.8)
                    let settled = sm * sm * (3 - 2 * sm)
                    let grown = fromSize.interpolated(to: toSize, progress: CGFloat(settled))
                    thickness = grown.thickness + fromSize.thickness * CGFloat(pop)
                    length = grown.length + fromSize.length * CGFloat(pop) * 0.3
                    let hop = dt - 0.22
                    if hop > 0, hop < 0.55 {
                        center.y -= CGFloat(sin(hop / 0.55 * .pi)) * 16
                    }
                    centerline = Worm.straightCenterline(center: center, length: length)
                }

                w.thickness = thickness

                // The body deforms and hops, but the contact shadow stays on
                // the moss plane. Tying it to the current body length keeps a
                // seed-sized worm and a fully-fed worm equally grounded while
                // they crawl in, settle, and react.
                var contactShadow = Path()
                let groundY = restCenter.y + thickness * 0.46
                for (index, point) in centerline.enumerated() {
                    let grounded = CGPoint(x: point.x, y: groundY)
                    if index == 0 {
                        contactShadow.move(to: grounded)
                    } else {
                        contactShadow.addLine(to: grounded)
                    }
                }
                context.drawLayer { shadow in
                    shadow.addFilter(.blur(radius: max(1, thickness * 0.12)))
                    shadow.stroke(
                        contactShadow,
                        with: .color(.black.opacity(0.16)),
                        style: StrokeStyle(
                            lineWidth: max(2, thickness * 0.34),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }

                w.draw(
                    in: context,
                    centerline: centerline,
                    time: t,
                    gaitWeights: gaitWeights,
                    wiggles: wiggles
                )
            }
            .overlay {
                HomeWormInteractionLayer(
                    center: restingCenter(at: t),
                    length: lengthAt(time: t),
                    thickness: thicknessAt(time: t),
                    isEnabled: isReadyForTouch(at: t),
                    onTap: onTap
                )
            }
        }
    }

    private func isReadyForTouch(at time: Double) -> Bool {
        guard let entranceStart else { return false }
        return time - entranceStart >= entranceDuration
    }

    private func restingCenter(at time: Double) -> CGPoint {
        guard let start = entranceStart, time - start >= entranceDuration else { return restCenter }
        var center = restCenter
        let settle = time - start - entranceDuration
        if settle > 0, settle < settleDuration {
            center.x += CGFloat(sin(settle / settleDuration * .pi) * exp(-settle * 3.0)) * 7
        }
        if let gulpStart {
            let hop = time - gulpStart - 0.22
            if hop > 0, hop < 0.55 {
                center.y -= CGFloat(sin(hop / 0.55 * .pi)) * 16
            }
        }
        return center
    }

    private func lengthAt(time: Double) -> CGFloat {
        guard let gulpStart else { return fromSize.length }
        let dt = max(0, time - gulpStart)
        let pop = dt < 0.16 ? dt / 0.16 : exp(-(dt - 0.16) * 2.4)
        let grown = fromSize.interpolated(to: toSize, progress: CGFloat(Self.smoothstep(min(1, dt / 0.8))))
        return grown.length + fromSize.length * CGFloat(pop) * 0.3
    }

    private func thicknessAt(time: Double) -> CGFloat {
        guard let gulpStart else { return fromSize.thickness }
        let dt = max(0, time - gulpStart)
        let pop = dt < 0.16 ? dt / 0.16 : exp(-(dt - 0.16) * 2.4)
        let grown = fromSize.interpolated(to: toSize, progress: CGFloat(Self.smoothstep(min(1, dt / 0.8))))
        return grown.thickness + fromSize.thickness * CGFloat(pop)
    }

    fileprivate static func headPosition(
        at time: Double,
        entranceStart: Double?,
        gulpStart: Double?,
        restCenter: CGPoint,
        fromSize: OnboardingWormSize,
        toSize: OnboardingWormSize,
        entranceDuration: Double,
        settleDuration: Double
    ) -> CGPoint {
        var center = restCenter
        var length = fromSize.length
        let thickness = fromSize.thickness
        var centerline: [CGPoint]
        var isEntering = true

        if let start = entranceStart {
            let dt = max(0, time - start)
            if dt < entranceDuration {
                centerline = inchwormEntranceCenterline(
                    restCenter: restCenter,
                    length: length,
                    thickness: thickness,
                    elapsed: dt,
                    duration: entranceDuration,
                    strides: 6
                )
            } else {
                isEntering = false
                let settle = dt - entranceDuration
                if settle > 0, settle < settleDuration {
                    center.x += CGFloat(sin(settle / settleDuration * .pi) * exp(-settle * 3.0)) * 7
                }
                centerline = Worm.straightCenterline(center: center, length: length)
            }
        } else {
            centerline = hiddenCenterline(restCenter: restCenter, length: length, thickness: thickness)
        }

        if !isEntering, let g = gulpStart {
            let dt = max(0, time - g)
            let pop = dt < 0.16 ? dt / 0.16 : exp(-(dt - 0.16) * 2.4)
            let sm = min(1, dt / 0.8)
            let settled = sm * sm * (3 - 2 * sm)
            let grown = fromSize.interpolated(to: toSize, progress: CGFloat(settled))
            length = grown.length + fromSize.length * CGFloat(pop) * 0.3
            let hop = dt - 0.22
            if hop > 0, hop < 0.55 {
                center.y -= CGFloat(sin(hop / 0.55 * .pi)) * 16
            }
            centerline = Worm.straightCenterline(center: center, length: length)
        }

        return centerline.last ?? restCenter
    }

    /// True inchworm entrance: head reaches forward while the tail anchors, then
    /// the tail catches up under an arched body.
    private static func inchwormEntranceCenterline(
        restCenter: CGPoint,
        length: CGFloat,
        thickness: CGFloat,
        elapsed: Double,
        duration: Double,
        strides: Int
    ) -> [CGPoint] {
        let p = min(max(elapsed / duration, 0), 1)
        guard p < 1 else { return Worm.straightCenterline(center: restCenter, length: length) }

        let strideCount = max(1, strides)
        let hiddenHead = -max(96, thickness * 5)
        let finalHead = restCenter.x + length / 2
        let strideDistance = (finalHead - hiddenHead) / CGFloat(strideCount)
        let scaled = min(Double(strideCount) - 0.0001, p * Double(strideCount))
        let strideIndex = CGFloat(floor(scaled))
        let phase = scaled - Double(strideIndex)

        let headBase = hiddenHead + strideIndex * strideDistance
        let tailBase = headBase - length
        let reachPortion = 0.52
        let tailX: CGFloat
        let headX: CGFloat
        let arch: CGFloat

        if phase < reachPortion {
            let reach = easeOutCubic(phase / reachPortion)
            tailX = tailBase
            headX = headBase + strideDistance * CGFloat(reach)
            arch = thickness * 0.55 * CGFloat(sin(reach * .pi))
        } else {
            let gather = (phase - reachPortion) / (1 - reachPortion)
            let eased = smoothstep(gather)
            tailX = tailBase + strideDistance * CGFloat(eased)
            headX = headBase + strideDistance
            arch = thickness * 2.15 * CGFloat(sin(gather * .pi))
        }

        return archedCenterline(tailX: tailX, headX: headX, y: restCenter.y, arch: arch)
    }

    private static func hiddenCenterline(restCenter: CGPoint, length: CGFloat, thickness: CGFloat) -> [CGPoint] {
        let headX = -max(96, thickness * 5)
        return archedCenterline(tailX: headX - length, headX: headX, y: restCenter.y, arch: 0)
    }

    private static func archedCenterline(tailX: CGFloat, headX: CGFloat, y: CGFloat, arch: CGFloat) -> [CGPoint] {
        let distance = max(1, headX - tailX)
        let steps = max(22, Int((distance / 4).rounded(.up)))
        return (0...steps).map { i in
            let u = CGFloat(i) / CGFloat(steps)
            return CGPoint(
                x: tailX + distance * u,
                y: y - arch * CGFloat(sin(Double(u) * .pi))
            )
        }
    }

    private static func easeOutCubic(_ x: Double) -> Double {
        1 - pow(1 - min(max(x, 0), 1), 3)
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Home's one interaction surface for the mascot. Keeping the hit target out
/// of the canvas means it is precise today and gives future worm controls a
/// single place to add their own gestures without making the whole screen live.
private struct HomeWormInteractionLayer: View {
    let center: CGPoint
    let length: CGFloat
    let thickness: CGFloat
    let isEnabled: Bool
    let onTap: (Double) -> Void

    var body: some View {
        let targetLength = max(length + 18, 44)
        let targetThickness = max(thickness + 22, 44)

        Capsule()
            // Nearly transparent rather than clear: it remains a concrete
            // capsule view for hit testing, never the enclosing overlay.
            .fill(Color.black.opacity(0.001))
            .frame(width: targetLength, height: targetThickness)
            .contentShape(Capsule())
            .gesture(SpatialTapGesture().onEnded { value in
                let bodyStart = (targetLength - length) / 2
                let origin = min(max(Double((value.location.x - bodyStart) / max(length, 1)), 0), 1)
                onTap(origin)
            })
            .position(center)
            .allowsHitTesting(isEnabled)
            .accessibilityLabel("Worm")
            .accessibilityAddTraits(.isButton)
    }
}

private struct HomeWormNameTag: View {
    let name: String
    let entranceStart: Double?
    let gulpStart: Double?
    let restCenter: CGPoint
    let fromSize: OnboardingWormSize
    let toSize: OnboardingWormSize
    let entranceDuration: Double
    let settleDuration: Double
    let viewport: CGSize
    let ink: Color
    let paper: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let head = HomeWorm.headPosition(
                at: time,
                entranceStart: entranceStart,
                gulpStart: gulpStart,
                restCenter: restCenter,
                fromSize: fromSize,
                toSize: toSize,
                entranceDuration: entranceDuration,
                settleDuration: settleDuration
            )
            let tagOffset = max(24, currentThickness(at: time) * 1.42)
            let x = min(max(head.x, 58), max(58, viewport.width - 58))
            let y = min(head.y + tagOffset, viewport.height - 38)
            
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: 112)
                .shadow(color: ink.opacity(0.08), radius: 5, y: 2)
                .position(x: x, y: y)
        }
    }

    private func currentThickness(at time: Double) -> CGFloat {
        guard let gulpStart else { return fromSize.thickness }

        let dt = max(0, time - gulpStart)
        let pop = dt < 0.16 ? dt / 0.16 : exp(-(dt - 0.16) * 2.4)
        let sm = min(1, dt / 0.8)
        let settled = sm * sm * (3 - 2 * sm)
        let grown = fromSize.interpolated(to: toSize, progress: CGFloat(settled))
        return grown.thickness + fromSize.thickness * CGFloat(pop)
    }
}

// MARK: - Morsels

struct FeedMorsel: Identifiable, Equatable {
    let entry: NodeCatalogEntry
    var id: String { entry.id }
}

/// The food: the node's emblem mapped onto a 2D apple (`FoodAppleView`). Same
/// grammar as the onboarding's music morsel, so "tap this and he eats it" is a
/// lesson the user already learned.
private struct FeedMorselView: View {
    let entry: NodeCatalogEntry
    let ink: Color
    let paper: Color

    var body: some View {
        FoodAppleView(entry: entry, size: 62, ink: ink, paper: paper)
            .contentShape(Circle().inset(by: -14))
    }
}

/// A slow vertical bob while the morsel hovers, waiting to be eaten.
private struct HoverBob: ViewModifier {
    var active: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: active && up ? -7 : 0)
            .animation(
                active ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : .default,
                value: up
            )
            .onAppear { up = true }
    }
}

/// A gentle grow + warm glow while the morsel waits to be eaten, so the apple
/// reads as tappable on its own — this is what replaced the "tap to feed" copy.
private struct AttentionPulse: ViewModifier {
    var active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && on ? 1.08 : 1.0)
            .shadow(color: .white.opacity(active && on ? 0.85 : 0.25),
                    radius: active && on ? 20 : 8)
            .shadow(color: Color(red: 0.98, green: 0.55, blue: 0.28).opacity(active && on ? 0.55 : 0),
                    radius: active && on ? 26 : 0)
            .animation(
                active ? .easeInOut(duration: 1.15).repeatForever(autoreverses: true) : .default,
                value: on
            )
            .onAppear { on = true }
    }
}

private struct BottomFlipModifier: ViewModifier {
    var progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: 72 * (1 - progress))
            .rotation3DEffect(
                .degrees(Double(-74 * (1 - progress))),
                axis: (x: 1, y: 0, z: 0),
                anchor: .bottom,
                perspective: 0.72
            )
    }
}

private struct NameTagPopModifier: ViewModifier {
    var progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
            .offset(y: 4 * (1 - progress))
    }
}

private extension AnyTransition {
    static var bottomFlip: AnyTransition {
        .modifier(
            active: BottomFlipModifier(progress: 0),
            identity: BottomFlipModifier(progress: 1)
        )
    }

    static var nameTagPop: AnyTransition {
        .modifier(
            active: NameTagPopModifier(progress: 0),
            identity: NameTagPopModifier(progress: 1)
        )
    }
}

#Preview {
    NavigationStack {
        WormHomeView()
    }
    .environment(SpotifyMusicNode())
    .environment(AppleMusicNode())
    .environment(YouTubeCultureNode())
    .environment(ContactsNode())
    .environment(PhotosNode())
    .environment(CalendarNode())
    .environment(SelfieNode())
    .environment(PromptNode())
    .environment(TasteProfile())
    .environment(NodeProgression(scheduler: UnlockNotificationScheduler()))
}
