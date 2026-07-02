import SwiftUI

/// The first-time experience. Splash has already drawn the worm in; this is the
/// soft intro → connect → **delight while it syncs**. As Spotify streams in, the
/// worm surfaces what it notices, one observation at a time, before the sync
/// ever finishes. That first "it gets me" is the whole point (`docs/vision.md`).
struct OnboardingView: View {
    @Environment(SpotifyMusicNode.self) private var spotify
    @Environment(TasteProfile.self) private var profile
    @AppStorage("worm.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var phase: Phase = .hello
    @State private var helloStep = 0
    @State private var revealed: [Insight] = []
    @State private var revealedIDs: Set<String> = []
    @State private var closingLine: String?
    @State private var canContinue = false
    @State private var isConnecting = false

    private enum Phase { case hello, intro, working, failed }

    private let helloLines = [
        "Hi.",
        "I'm your worm.",
        "Show me who you are…",
        "…and I'll dig up music you'll love.",
    ]

    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    private let ink = Color.black

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()

            switch phase {
            case .hello: helloView
            case .intro: introView
            case .working: workingView
            case .failed: failedView
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    // MARK: - Hello (the worm introduces itself)

    /// Where the worm sits at each step — it inches to the next spot as you tap.
    private let helloSpots: [UnitPoint] = [
        UnitPoint(x: 0.50, y: 0.30),
        UnitPoint(x: 0.28, y: 0.24),
        UnitPoint(x: 0.74, y: 0.33),
        UnitPoint(x: 0.46, y: 0.27),
    ]

    private var helloView: some View {
        GeometryReader { geo in
            let spot = helloSpots[min(helloStep, helloSpots.count - 1)]
            ZStack {
                // The worm CRAWLS to its new spot on each step — TravelingWorm owns
                // worm locomotion, so this inches like a worm, not a float.
                TravelingWorm(
                    target: CGPoint(x: geo.size.width * spot.x, y: geo.size.height * spot.y),
                    color: ink.opacity(0.9),
                    eyeColor: paper
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer()
                    Text(helloLines[helloStep])
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .id(helloStep)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    Spacer()

                    Group {
                        if helloStep >= helloLines.count - 1 {
                            Button(action: { Haptics.impact(.medium); withAnimation(.easeInOut(duration: 1.1)) { phase = .intro } }) {
                                Text("Let's go")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(paper)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(ink, in: Capsule())
                            }
                            .padding(.horizontal, 32)
                            .transition(.opacity)
                        } else {
                            Text("tap to continue")
                                .font(.system(size: 14))
                                .foregroundStyle(ink.opacity(0.35))
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: advanceHello)
        }
    }

    private func advanceHello() {
        guard helloStep < helloLines.count - 1 else { return }
        Haptics.impact(.light, intensity: 0.6)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { helloStep += 1 }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 28) {
            Spacer()
            InchwormLoader(color: ink.opacity(0.9), eyeColor: paper)
                .frame(width: 128, height: 76)

            VStack(spacing: 10) {
                (Text("Let's start off easy."))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.88))
                Text("So that i can get to know you.")
                    .font(.system(size: 16))
                    .foregroundStyle(ink.opacity(0.5))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)

            Spacer()

            VStack(spacing: 14) {
                Button(action: startWorking) {
                    Group {
                        if isConnecting {
                            ProgressView().tint(paper)
                        } else {
                            Text("Connect Spotify").font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundStyle(paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(ink, in: Capsule())
                }
                .disabled(isConnecting)

                Button("Not now") { finish() }
                    .font(.system(size: 15))
                    .foregroundStyle(ink.opacity(0.45))
                    .opacity(isConnecting ? 0 : 1)
                    .disabled(isConnecting)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Working (the delight)

    private var workingView: some View {
        VStack(spacing: 0) {
            InchwormLoader(color: ink.opacity(0.9), eyeColor: paper)
                .frame(width: 88, height: 52)
                .padding(.top, 44)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        Color.clear.frame(height: 180)

                        ForEach(revealed) { insight in
                            Text(insight.line)
                                .font(.system(size: 27, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink.opacity(isActive(insight) ? 0.9 : 0.32))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(insight.id)
                                .animation(.easeInOut(duration: 0.4), value: revealed.count)
                                .transition(.opacity)
                        }

                        if let closingLine {
                            Text(closingLine)
                                .font(.system(size: 29, weight: .bold, design: .rounded))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("closing")
                                .transition(.opacity)
                        } else {
                            PulsingEllipsis(color: ink)
                                .padding(.top, 4)
                                .id("working")
                        }

                        Color.clear.frame(height: 260)
                    }
                    .padding(.horizontal, 34)
                }
                .scrollIndicators(.hidden)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.14),
                            .init(color: .black, location: 0.82),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .onAppear { recenter(proxy) }
                .onChange(of: revealed.count) { recenter(proxy) }
                .onChange(of: closingLine) { recenter(proxy, onClosing: closingLine != nil) }
            }

            if canContinue {
                Button(action: finish) {
                    Text(revealed.isEmpty ? "Continue" : "That's me.")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(ink, in: Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: phase) { await runFTUE() }
        .task(id: isLoadingFirstInsight) { await pulseLoadingHaptics() }
    }

    /// True only while waiting on the very first insight (the dots phase).
    private var isLoadingFirstInsight: Bool {
        phase == .working && revealed.isEmpty && closingLine == nil
    }

    /// Soft, rolling taps in time with the loading dots — the three-dot wave you
    /// can feel. Stops the instant the first insight lands.
    private func pulseLoadingHaptics() async {
        while !Task.isCancelled, isLoadingFirstInsight {
            for _ in 0..<3 {
                if Task.isCancelled || !isLoadingFirstInsight { return }
                Haptics.impact(.light, intensity: 0.5)
                try? await Task.sleep(for: .seconds(0.16))
            }
            try? await Task.sleep(for: .seconds(0.7))
        }
    }

    private func isActive(_ insight: Insight) -> Bool {
        closingLine == nil && insight.id == revealed.last?.id
    }

    private func recenter(_ proxy: ScrollViewProxy, onClosing: Bool = false) {
        withAnimation(.easeInOut(duration: 0.5)) {
            proxy.scrollTo(onClosing ? "closing" : (revealed.last?.id ?? "working"), anchor: .center)
        }
    }

    // MARK: - Failed

    private var failedView: some View {
        VStack(spacing: 22) {
            Spacer()
            InchwormLoader(color: ink.opacity(0.8), eyeColor: paper)
                .frame(width: 120, height: 70)
            Text(spotify.lastErrorMessage ?? "Couldn't connect to Spotify.")
                .font(.system(size: 17))
                .foregroundStyle(ink.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            VStack(spacing: 14) {
                Button(action: { phase = .intro }) {
                    Text("Try again")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(ink, in: Capsule())
                }
                Button("Not now") { finish() }
                    .font(.system(size: 15))
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Logic

    /// Minimum time a line stays alone before the next arrives — let each land.
    private let revealGap: Duration = .seconds(4.5)
    /// Don't wait forever on the long tail of the sync before synthesizing.
    private let dataTimeout: TimeInterval = 45

    /// Connect runs on the intro screen. We stay here until the OAuth sheet
    /// closes WITH permissions granted, then move to the working screen — so the
    /// dots never show behind or before the Spotify web view.
    private func startWorking() {
        guard !isConnecting else { return }
        isConnecting = true
        Haptics.impact(.medium)
        Task { await spotify.connect() }   // presents the OAuth sheet
        Task { await waitForAuthThenProceed() }
    }

    private func waitForAuthThenProceed() async {
        let start = Date()
        var sawAuthorizing = false
        while !spotify.isAuthorized {
            if Task.isCancelled { return }
            if spotify.isAuthorizing { sawAuthorizing = true }
            // Sheet closed without perms (cancelled / denied / failed).
            let settled = !spotify.isAuthorizing
            let longEnough = sawAuthorizing || Date().timeIntervalSince(start) > 2
            if settled, longEnough, spotify.lastErrorMessage != nil {
                isConnecting = false
                phase = .failed
                return
            }
            try? await Task.sleep(for: .seconds(0.15))
        }

        // Permissions granted, the web view is gone — now reveal the worm working.
        isConnecting = false
        revealed = []
        revealedIDs = []
        closingLine = nil
        canContinue = false
        phase = .working
    }

    /// Drives the first run by *tapping the taste profile* — it doesn't author
    /// insights, it asks the entity to synthesize and reveals what comes back.
    /// By the time this runs we're already authorized (the intro held until then).
    private func runFTUE() async {
        guard phase == .working else { return }

        // The sync fetches top artists + playlist titles first, so the richest
        // material is ready fast. One strong pass off that — no generic warm-up.
        await waitUntil(timeout: dataTimeout) {
            let settled = !self.spotify.isSyncing && !self.spotify.isAuthorizing
            let rich = !self.spotify.topArtistsShort.isEmpty && !self.spotify.playlists.isEmpty
            return settled || rich
        }
        await profile.synthesize(slices: [BrainSliceBuilder.spotifySlice(from: spotify)], mode: .quick)
        await revealPending()

        await closeOnGreeting()
    }

    /// Polls until `condition` holds or `timeout` elapses.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async {
        let start = Date()
        while !condition(), Date().timeIntervalSince(start) < timeout, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.25))
        }
    }

    /// Reveals any insights the entity holds that we haven't shown yet, paced.
    private func revealPending() async {
        for insight in profile.insights where !revealedIDs.contains(insight.id) {
            if Task.isCancelled { return }
            reveal(insight)
            try? await Task.sleep(for: revealGap)
        }
    }

    private func reveal(_ insight: Insight) {
        revealedIDs.insert(insight.id)
        Haptics.impact(.heavy)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            revealed.append(insight)
        }
    }

    /// The closing beat: the worm meets you by name, then offers the way in.
    private func closeOnGreeting() async {
        try? await Task.sleep(for: .seconds(0.9))
        let line = resolvedName.map { "It's nice to meet you, \($0).\n\nI like your vibe." } ?? "It's nice to meet you.\n\nI like your vibe."
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { closingLine = line }
        try? await Task.sleep(for: .seconds(0.5))
        withAnimation(.easeOut(duration: 0.4)) { canContinue = true }
    }

    private var resolvedName: String? {
        if let stored = UserDefaults.standard.string(forKey: "worm.userName")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return stored
        }
        if let displayName = spotify.profile?.displayName, !displayName.isEmpty {
            return displayName.split(separator: " ").first.map(String.init)
        }
        return nil
    }

    private func finish() {
        Haptics.success()
        hasCompletedOnboarding = true
    }
}

/// Three greyed dots that breathe in a wave, one after another — the worm is
/// still thinking. A little more alive than a single pulse.
private struct PulsingEllipsis: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 11) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(color.opacity(opacity(at: t, dot: i)))
                        .frame(width: 13, height: 13)
                }
            }
        }
    }

    /// A travelling wave: each dot lags the one before it.
    private func opacity(at time: Double, dot: Int) -> Double {
        let wave = sin(time * 2.4 - Double(dot) * 0.95)
        return 0.1 + 0.42 * (0.5 + 0.5 * wave)
    }
}

#Preview {
    OnboardingView()
        .environment(SpotifyMusicNode())
        .environment(TasteProfile())
}
