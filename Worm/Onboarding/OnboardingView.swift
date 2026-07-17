import SwiftUI

/// The first-time experience. Splash has already drawn the worm in; this is the
/// soft intro → connect → **one real reveal**. Spotify is the only populated
/// node at this point, so the first "it gets me" moment is a single taste-profile
/// draw from that slice, not a canned line.
struct OnboardingView: View {
    /// Demo replay (from Profile): the exact first-run flow, except the
    /// Spotify connect is a ghost — no OAuth, and the reveal is a template
    /// insight — so the whole FTUE story into home can be watched anytime.
    var demo = false
    var onFinished: (() -> Void)? = nil

    @Environment(SpotifyMusicNode.self) private var spotify
    @Environment(SelfieNode.self) private var selfie
    @Environment(TasteProfile.self) private var profile
    @AppStorage("worm.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var phase: Phase = .hello
    @State private var helloStep = 0
    /// The worm stretching out — continuously — to swallow the whole screen.
    @State private var growing = false
    /// Wall-clock moment the stretch began; drives the length growth per frame.
    @State private var growthStart: Double?
    /// Beat-by-beat reveals on the "this is your worm" step.
    @State private var continueVisible = true
    @State private var showDownHere = false
    /// The white "Let's go" landing once the screen has gone black.
    @State private var showLetsGo = false
    @State private var revealed: [Insight] = []
    @State private var revealedIDs: Set<String> = []
    @State private var canContinue = false
    @State private var isConnecting = false
    /// Beat-by-beat reveals on the "Let's start off  easy" step.
    @State private var askRevealed = false
    @State private var snapButtonVisible = false
    /// Beat-by-beat reveals on the "now the music" (Spotify) step.
    @State private var spotifyAskRevealed = false
    @State private var spotifyButtonVisible = false
    /// The worm's learned size across the onboarding asks.
    @State private var wormSize = Worm.Size.seed
    /// Music-success swallow state. This keeps the OAuth success connected to
    /// the same growth language as the selfie.
    @State private var spotifyContentHidden = false
    @State private var musicMorselVisible = false
    @State private var musicMorselFed = false
    @State private var musicGulpStart: Double?

    private enum Phase { case hello, intro, selfie, spotify, working, failed }

    private let helloLines = [
        "Hi.",
        "this is your worm",
        "the more he learns about you…",
        "…the better he gets at understanding your taste",
    ]

    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    private let ink = Color.black

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()

            switch phase {
            case .hello: helloView
            case .intro: introView
            case .selfie: SelfieCaptureView(ink: ink, paper: paper, onDone: {
                    // Kick off the vision read of the just-captured selfie in the
                    // background so it's ready by the time the profile synthesizes,
                    // then move on to the Spotify ask.
                    Task { await selfie.ingestCapturedSelfie() }
                    wormSize = .afterSelfie
                    resetSpotifyAsk()
                    phase = .spotify
                })
            case .spotify: spotifyIntroView
            case .working: workingView
            case .failed: failedView
            }
        }
        .animation(.easeInOut(duration: 0.85), value: phase)
    }

    // MARK: - Hello (the worm introduces itself, then eats the screen)

    /// A barely-there dot of a worm — short body, almost no inch. It only comes
    /// alive when it starts to grow.
    private let dotWorm = Worm.character

    private var helloView: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let restY = H * 0.74          // the dot sits low, near "tap to continue"

            ZStack {
                // The little guy, drawn into a FULL-SCREEN canvas. He grows like a
                // balloon animal being blown up: longer and fatter, curling around
                // himself until his own ink IS the whole screen — no background
                // fade, just worm.
                GrowingWorm(
                    growthStart: growthStart,
                    screen: geo.size,
                    restCenter: CGPoint(x: W / 2, y: restY),
                    restingSize: wormSize,
                    color: ink,
                    eyeColor: paper,
                    worm: dotWorm
                )
                .allowsHitTesting(false)

                if helloStep == 1 && showDownHere {
                    Text("down here!")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.4))
                        .position(x: W / 2, y: restY + 40)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    Spacer().frame(height: H * 0.28)
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
                        // Stays up the whole grow — it's dark ink on top, so the
                        // worm simply swallows it as its black fill reaches it.

                    // Paper on paper, so it's invisible until the worm's black
                    // body rolls over it — the grow itself reveals the line.
                    if helloStep == helloLines.count - 1 {
                        Text("and the more he grows")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(paper)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 14)
                    }

                    Spacer()

                    Group {
                        if showLetsGo {
                            Button(action: { Haptics.impact(.medium); phase = .intro }) {
                                Text("Let's go")
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .transition(.opacity)
                        } else if continueVisible && !growing {
                            Text("tap to continue")
                                .font(.system(size: 14))
                                .foregroundStyle(ink.opacity(0.35))
                                .transition(.opacity)
                        }
                    }
                    .padding(.bottom, 44)
                }
            }
            .frame(width: W, height: H)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: advanceHello)
    }

    private func advanceHello() {
        guard !growing else { return }
        let next = helloStep + 1
        guard next <= helloLines.count - 1 else { return }
        Haptics.impact(.light, intensity: 0.6)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { helloStep = next }

        switch next {
        case 1:
            // "this is your worm" — reveal "down here!" then the prompt, a beat apart.
            withAnimation(.easeOut(duration: 0.3)) { continueVisible = false }
            showDownHere = false
            scheduleStep1Beats()
        case 2:
            withAnimation(.easeIn(duration: 0.3)) { continueVisible = true }
        case helloLines.count - 1:
            beginGrowth()
        default:
            break
        }
    }

    /// "down here!" a couple seconds later, then the "tap to continue" after that.
    private func scheduleStep1Beats() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                guard helloStep == 1 else { return }
                Haptics.impact(.light, intensity: 0.4)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showDownHere = true }
            }
            try? await Task.sleep(for: .seconds(1.3))
            await MainActor.run {
                guard helloStep == 1 else { return }
                withAnimation(.easeIn(duration: 0.4)) { continueVisible = true }
            }
        }
    }

    /// The payoff: the worm just keeps growing — longer, fatter, curling over
    /// itself — until the screen is all worm, then white "Let's go" lands.
    private func beginGrowth() {
        growing = true            // lock out taps right away
        continueVisible = false
        Task {
            // A beat to let the last line land and be read before he takes off.
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                growthStart = Date().timeIntervalSinceReferenceDate
                Haptics.impact(.heavy)
            }
            try? await Task.sleep(for: .seconds(8.6))   // GrowingWorm.duration + a beat
            await MainActor.run {
                Haptics.impact(.rigid)
                withAnimation(.easeOut(duration: 0.5)) { showLetsGo = true }
            }
        }
    }

    private func resetSpotifyAsk() {
        spotifyAskRevealed = false
        spotifyButtonVisible = false
        spotifyContentHidden = false
        musicMorselVisible = false
        musicMorselFed = false
        musicGulpStart = nil
        isConnecting = false
    }

    // MARK: - Intro (the first ask: a selfie)

    private var introView: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height

            ZStack {
                // The same little guy from the hello screen, back to a resting dot
                // low on the screen — a familiar face to greet the first ask.
                SnackingWorm(
                    restCenter: CGPoint(x: W / 2, y: H * 0.72),
                    gulpStart: nil,
                    fromSize: wormSize,
                    toSize: wormSize,
                    color: ink,
                    eyeColor: paper
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer().frame(height: H * 0.22)

                    // "Let's start off easy." holds on its own, then the selfie ask
                    // takes its place — the next step, not a line stacked under it.
                    ZStack {
                        if askRevealed {
                            VStack(spacing: 10) {
                                Text("a quick selfie")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ink.opacity(0.88))
                                Text("so I can put a face to the taste.")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(ink.opacity(0.5))
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            Text("Let's start off easy.")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink.opacity(0.88))
                                .transition(.opacity)
                        }
                    }

                    Spacer()

                    if snapButtonVisible {
                        Button(action: { Haptics.impact(.medium); phase = .selfie }) {
                            Text("take it")
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
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            }
            .task { await scheduleIntroBeats() }
        }
    }

    /// The title holds a moment, then the selfie ask replaces it, the button a
    /// beat after that.
    private func scheduleIntroBeats() async {
        guard !askRevealed else { return }
        try? await Task.sleep(for: .seconds(2.1))
        guard phase == .intro else { return }
        Haptics.impact(.light, intensity: 0.5)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { askRevealed = true }
        try? await Task.sleep(for: .seconds(1.7))
        guard phase == .intro else { return }
        withAnimation(.easeIn(duration: 0.4)) { snapButtonVisible = true }
    }

    // MARK: - Spotify (the second ask: connect the music)

    /// Same shape as the selfie ask — the little guy waits low, the title holds,
    /// then the ask replaces it and the connect button follows a beat later.
    private var spotifyIntroView: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let wormCenter = CGPoint(x: W / 2, y: H * 0.72)
            let morselStart = CGPoint(x: W / 2, y: H * 0.54)

            ZStack {
                SnackingWorm(
                    restCenter: wormCenter,
                    gulpStart: musicGulpStart,
                    fromSize: .afterSelfie,
                    toSize: .afterMusic,
                    color: ink,
                    eyeColor: paper
                )
                .allowsHitTesting(false)

                if musicMorselVisible {
                    MusicConnectionMorsel(ink: ink, paper: paper)
                        .scaleEffect(musicMorselFed ? 0.08 : 1)
                        .rotationEffect(.degrees(musicMorselFed ? 20 : -8))
                        .position(musicMorselFed ? wormCenter : morselStart)
                        .opacity(musicGulpStart == nil ? 1 : 0)
                        .transition(.scale(scale: 0.35).combined(with: .opacity))
                }

                if !spotifyContentHidden {
                    VStack(spacing: 0) {
                        Spacer().frame(height: H * 0.22)

                        ZStack {
                            if spotifyAskRevealed {
                                VStack(spacing: 10) {
                                    Text("the music")
                                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                                        .foregroundStyle(ink.opacity(0.88))
                                    Text("connect Spotify so I can know what you like.")
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundStyle(ink.opacity(0.5))
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else {
                                Text("good. now the fun part.")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ink.opacity(0.88))
                                    .transition(.opacity)
                            }
                        }

                        Spacer()

                        if spotifyButtonVisible {
                            Button(action: startWorking) {
                                Text(isConnecting ? "connecting…" : "connect Spotify")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(paper)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(ink, in: Capsule())
                            }
                            .disabled(isConnecting)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .transition(.opacity)
                }
            }
            .task { await scheduleSpotifyBeats() }
        }
    }

    /// The connect ask replaces the title, the button a beat after that — matched
    /// to the selfie step's cadence so it reads as the next step in one flow.
    private func scheduleSpotifyBeats() async {
        guard !spotifyAskRevealed, !spotifyContentHidden else { return }
        try? await Task.sleep(for: .seconds(2.1))
        guard phase == .spotify, !spotifyContentHidden else { return }
        Haptics.impact(.light, intensity: 0.5)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { spotifyAskRevealed = true }
        try? await Task.sleep(for: .seconds(1.7))
        guard phase == .spotify, !spotifyContentHidden else { return }
        withAnimation(.easeIn(duration: 0.4)) { spotifyButtonVisible = true }
    }

    // MARK: - Working (the delight)

    private var workingView: some View {
        ZStack {
            TasteRevealBackdrop(color: ink)

            VStack(spacing: 0) {
                Spacer(minLength: 34)

                ZStack {
                    if let insight = revealed.first {
                        FirstInsightReveal(insight: insight, ink: ink)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    } else {
                        TasteScanLoader(ink: ink, paper: paper, wormSize: wormSize)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if canContinue {
                    Button(action: finish) {
                        Text(revealed.isEmpty ? "Keep digging" : "That's me.")
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
        }
        .task(id: phase) { await runFTUE() }
        .task(id: isLoadingFirstInsight) { await pulseLoadingHaptics() }
    }

    /// True only while waiting on the very first insight (the dots phase).
    private var isLoadingFirstInsight: Bool {
        phase == .working && revealed.isEmpty
    }

    /// Soft, rolling taps in time with the dig animation. Stops the instant the
    /// real insight lands.
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

    // MARK: - Failed

    private var failedView: some View {
        VStack(spacing: 22) {
            Spacer()
            OnboardingWormGlyph(size: wormSize, color: ink.opacity(0.8), eyeColor: paper)
                .frame(width: 120, height: 70)
            Text(spotify.lastErrorMessage ?? "Couldn't connect to Spotify.")
                .font(.system(size: 17))
                .foregroundStyle(ink.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            VStack(spacing: 14) {
                Button(action: { spotifyButtonVisible = true; phase = .spotify }) {
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

    /// Connect runs on the intro screen. We stay here until the OAuth sheet
    /// closes WITH permissions granted, then move to the working screen — so the
    /// dots never show behind or before the Spotify web view.
    private func startWorking() {
        guard !isConnecting else { return }
        isConnecting = true
        Haptics.impact(.medium)
        if demo {
            // Ghost connect: no OAuth sheet, straight into the same
            // feed-the-worm beat the real flow lands on.
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                isConnecting = false
                await absorbMusicThenProceed()
            }
            return
        }
        let startingAuthorizationVersion = spotify.authorizationVersion
        Task { await spotify.connectForOnboarding() }   // presents the OAuth sheet
        Task { await waitForAuthThenProceed(after: startingAuthorizationVersion) }
    }

    private func waitForAuthThenProceed(after startingAuthorizationVersion: Int) async {
        let start = Date()
        var sawAuthorizing = false
        while !spotify.isAuthorized || spotify.authorizationVersion <= startingAuthorizationVersion {
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

        // Permissions granted, the web view is gone — now the music connection
        // becomes food, grows the worm, and only then reveals him working.
        isConnecting = false
        await absorbMusicThenProceed()
    }

    private func absorbMusicThenProceed() async {
        withAnimation(.easeOut(duration: 0.25)) {
            spotifyContentHidden = true
            spotifyButtonVisible = false
        }

        try? await Task.sleep(for: .seconds(0.18))
        Haptics.impact(.light, intensity: 0.55)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            musicMorselVisible = true
        }

        try? await Task.sleep(for: .seconds(0.5))
        Haptics.impact(.medium)
        withAnimation(.easeIn(duration: 0.72)) {
            musicMorselFed = true
        }

        try? await Task.sleep(for: .seconds(0.72))
        musicGulpStart = Date().timeIntervalSinceReferenceDate
        wormSize = .afterMusic
        Haptics.impact(.heavy)

        try? await Task.sleep(for: .seconds(1.0))
        withAnimation(.easeOut(duration: 0.24)) {
            musicMorselVisible = false
        }

        try? await Task.sleep(for: .seconds(0.35))
        revealed = []
        revealedIDs = []
        canContinue = false
        phase = .working
    }

    /// Drives the first run by *tapping the taste profile* — it doesn't author
    /// insights, it asks the entity to synthesize and reveals what comes back.
    /// By the time this runs we're already authorized (the intro held until then).
    private func runFTUE() async {
        guard phase == .working else { return }

        guard !Task.isCancelled else { return }
        if demo {
            // Template insight: the dig loader breathes for a couple of
            // beats, then a canned on-voice line lands the reveal.
            try? await Task.sleep(for: .seconds(2.6))
            guard phase == .working, !Task.isCancelled else { return }
            reveal(Insight(
                line: "You never actually left 2006.",
                evidence: "demo template",
                confidence: 0.9,
                source: .spotify
            ))
            try? await Task.sleep(for: .seconds(1.1))
        } else if let insight = await FirstInsightPipeline.runSpotifyFirstInsight(
            spotify: spotify,
            profile: profile,
            selfie: selfie
        ) {
            reveal(insight)
            try? await Task.sleep(for: .seconds(1.1))
        }

        withAnimation(.easeOut(duration: 0.4)) { canContinue = true }
    }

    private func reveal(_ insight: Insight) {
        guard !revealedIDs.contains(insight.id) else { return }
        revealedIDs.insert(insight.id)
        Haptics.impact(.heavy)
        withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
            revealed = [insight]
        }
    }

    private func finish() {
        Haptics.success()
        if demo {
            onFinished?()
        } else {
            hasCompletedOnboarding = true
        }
    }
}

/// The onboarding worm, drawn into a full-screen canvas so it's never clipped by
/// a box. At rest it's a tiny dot; once `growing` flips, he inflates like a
/// balloon animal — the body gets LONGER and FATTER together, first curling
/// around his resting spot, then coiling back and forth up the screen (each coil
/// with its own wave and spacing, so it never looks printed) until the ink is
/// the whole screen. Driven by the timeline clock (not a state animation) so the
/// growth is genuinely continuous, and the tail never leaves the resting spot.
private struct GrowingWorm: View {
    /// Wall-clock start of the growth (nil = resting dot).
    var growthStart: Double?
    var screen: CGSize
    var restCenter: CGPoint
    var restingSize: Worm.Size
    var color: Color
    var eyeColor: Color?
    var worm: Worm = .character
    /// How long the full inflation takes.
    var duration: Double = 8.4

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in
                var w = worm
                w.color = color
                w.eyeColor = eyeColor   // the head keeps its face the whole way

                let centerline: [CGPoint]
                if let start = growthStart {
                    let p = min(1, max(0, (t - start) / duration))
                    // Slow first breath, big whoosh through the middle, soft
                    // landing as the last sliver of paper goes dark.
                    let ease = p * p * (3 - 2 * p)
                    let fat = Self.finalThickness(for: screen)
                    let path = Self.growthPath(screen: screen, from: restCenter, finalThickness: fat)
                    let total = Self.length(of: path)
                    let drawn = restingSize.length + (total - restingSize.length) * CGFloat(ease)
                    centerline = Self.prefix(path, length: drawn)
                    // Inflate slightly ahead of the stretch, like a balloon.
                    w.thickness = restingSize.thickness
                        + (fat - restingSize.thickness) * CGFloat(pow(ease, 0.7))
                    // Wriggle hard while small, settle as he fills in — a moving
                    // gait on a screen-wide body would crack the solid black.
                    w.gaitHeightRatio *= (1 - 0.85 * ease)
                } else {
                    // Resting dot: a stubby horizontal nub with eyes.
                    let x0 = restCenter.x - restingSize.length / 2
                    centerline = (0...10).map {
                        CGPoint(x: x0 + restingSize.length * CGFloat($0) / 10, y: restCenter.y)
                    }
                    w.thickness = restingSize.thickness
                }

                guard centerline.count >= 2 else { return }
                w.draw(in: context, centerline: centerline, time: t)
            }
        }
    }

    /// Fully grown, the body is a good chunk of the screen wide — that's what
    /// lets a single strand swallow everything without racing.
    private static func finalThickness(for screen: CGSize) -> CGFloat {
        max(64, min(screen.width, screen.height) * 0.28)
    }

    /// One continuous strand, densely sampled (every point ~10pt from the last,
    /// so the body never breaks into dots): a lazy curl around the resting spot,
    /// a dive under everything to the bottom edge, then loose coils climbing the
    /// screen. Every coil gets its own wave shape and its own spacing — jittered,
    /// but always under the final body width, so the takeover looks improvised
    /// while still ending gapless. The head slips off the top at the very end.
    private static func growthPath(screen: CGSize, from rest: CGPoint, finalThickness fat: CGFloat) -> [CGPoint] {
        let step: CGFloat = 10
        var pts: [CGPoint] = [rest]

        // Frame-stable "randomness": same screen, same silly path every frame.
        func rnd(_ i: Int, _ salt: Double) -> Double {
            let v = sin(Double(i) * 127.1 + salt * 311.7) * 43758.5453
            return v - v.rounded(.down)
        }

        // Densely sampled segment to `target`, bulging sideways by `bend` at its
        // midpoint so connectors read as body, not wire.
        func appendCurve(to target: CGPoint, bend: CGFloat = 0) {
            guard let a = pts.last else { return }
            let d = max(hypot(target.x - a.x, target.y - a.y), 0.001)
            let nx = -(target.y - a.y) / d
            let ny = (target.x - a.x) / d
            let n = max(2, Int(d / step))
            for k in 1...n {
                let f = CGFloat(k) / CGFloat(n)
                let arch = CGFloat(sin(Double(f) * .pi))
                pts.append(CGPoint(
                    x: a.x + (target.x - a.x) * f + nx * bend * arch,
                    y: a.y + (target.y - a.y) * f + ny * bend * arch
                ))
            }
        }

        // 1) He curls up on the spot first — an outward coil, winding-hose style.
        var theta = 0.0
        let coilGap: CGFloat = 24
        while theta < 2.6 * 2 * .pi {
            let r = CGFloat(theta / (2 * .pi)) * coilGap * (1 + 0.1 * CGFloat(sin(theta * 2.3)))
            pts.append(CGPoint(
                x: rest.x + cos(theta + .pi / 2) * r * 1.2,
                y: rest.y + sin(theta + .pi / 2) * r * 0.85
            ))
            theta += Double(step / max(r, 10))
        }

        // 2) Dive under everything so the fill starts from the bottom edge up —
        // the black spreads outward from where he lives, not from a far corner.
        appendCurve(to: CGPoint(x: screen.width * 0.22, y: screen.height + fat * 0.2), bend: 30)

        // 3) Coil back and forth up the screen.
        let inset = fat * 0.28
        var y = screen.height + fat * 0.2
        var row = 0
        var leftToRight = true
        while y > -fat * 0.3 {
            let amp = fat * CGFloat(0.05 + 0.10 * rnd(row, 1))
            let humps = 1.0 + 2.4 * rnd(row, 2)
            let phase = rnd(row, 3) * 2 * .pi
            let x0 = leftToRight ? -inset : screen.width + inset
            let x1 = leftToRight ? screen.width + inset : -inset
            let n = max(2, Int(abs(x1 - x0) / step))
            for k in 0...n {
                let f = CGFloat(k) / CGFloat(n)
                let wave = sin(Double(f) * humps * 2 * .pi + phase) * Double(amp)
                pts.append(CGPoint(x: x0 + (x1 - x0) * f, y: y + CGFloat(wave)))
            }
            // Turn around at the edge with a little outward bulge, and pick a
            // fresh gap for the next coil (always under the final body width).
            let gap = fat * CGFloat(0.42 + 0.14 * rnd(row, 4))
            appendCurve(
                to: CGPoint(x: x1, y: y - gap),
                bend: leftToRight ? fat * 0.15 : -fat * 0.15
            )
            y -= gap
            row += 1
            leftToRight.toggle()
        }

        // 4) And out — the head slips off the top of the screen.
        if let last = pts.last {
            appendCurve(to: CGPoint(x: last.x, y: -fat * 1.4))
        }
        return pts
    }

    private static func length(of path: [CGPoint]) -> CGFloat {
        guard path.count >= 2 else { return 0 }
        var acc: CGFloat = 0
        for i in 1..<path.count {
            acc += hypot(path[i].x - path[i - 1].x, path[i].y - path[i - 1].y)
        }
        return acc
    }

    /// The leading `length` of the path, with a final point interpolated exactly
    /// at the cut so the growing tip advances smoothly.
    private static func prefix(_ path: [CGPoint], length: CGFloat) -> [CGPoint] {
        guard let first = path.first else { return [] }
        var out = [first]
        var acc: CGFloat = 0
        for i in 1..<path.count {
            let seg = hypot(path[i].x - path[i - 1].x, path[i].y - path[i - 1].y)
            if acc + seg >= length {
                let f = (length - acc) / max(seg, 0.0001)
                out.append(CGPoint(x: path[i - 1].x + (path[i].x - path[i - 1].x) * f,
                                   y: path[i - 1].y + (path[i].y - path[i - 1].y) * f))
                return out
            }
            acc += seg
            out.append(path[i])
        }
        return out
    }
}

private struct TasteRevealBackdrop: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for line in 0..<10 {
                    let baseY = size.height * (0.12 + CGFloat(line) * 0.085)
                    let phase = t * 0.45 + Double(line) * 0.8
                    var path = Path()
                    for step in 0...28 {
                        let progress = CGFloat(step) / 28
                        let x = -24 + (size.width + 48) * progress
                        let y = baseY
                            + CGFloat(sin(Double(progress) * 5.0 + phase)) * 7
                            + CGFloat(sin(Double(progress) * 11.0 - phase)) * 2
                        if step == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    context.stroke(
                        path,
                        with: .color(color.opacity(line.isMultiple(of: 2) ? 0.045 : 0.028)),
                        lineWidth: line.isMultiple(of: 3) ? 1.6 : 1
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct TasteScanLoader: View {
    let ink: Color
    let paper: Color
    let wormSize: Worm.Size

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 24) {
                ZStack {
                    BurrowPulse(color: ink, time: t)
                        .frame(width: 220, height: 116)
                    OnboardingWormGlyph(size: wormSize, color: ink.opacity(0.9), eyeColor: paper)
                        .frame(width: max(168, wormSize.length + 52), height: 86)
                        .offset(y: -4)
                }

                Text("digging through your music")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.5))
            }
            .padding(.bottom, 36)
        }
    }
}

private struct MusicConnectionMorsel: View {
    let ink: Color
    let paper: Color

    // The music node's food apple, so onboarding teaches the same "tap to eat"
    // grammar the home morsel uses. Only the glyph fallback (music.note) shows
    // until a real emblem is set for it.
    private static let musicEntry = NodeCatalog.entry("apple-music") ?? NodeCatalog.source[0]

    var body: some View {
        FoodAppleView(entry: Self.musicEntry, size: 62, ink: ink, paper: paper)
    }
}

private struct BurrowPulse: View {
    let color: Color
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0..<4 {
                let age = (time * 0.48 + Double(index) * 0.22).truncatingRemainder(dividingBy: 1)
                let width = size.width * (0.46 + CGFloat(age) * 0.5)
                let height = size.height * (0.34 + CGFloat(age) * 0.42)
                let rect = CGRect(
                    x: center.x - width / 2,
                    y: center.y - height / 2,
                    width: width,
                    height: height
                )
                var path = Path()
                path.addEllipse(in: rect)
                context.stroke(path, with: .color(color.opacity(0.11 * (1 - age))), lineWidth: 1.2)
            }
        }
    }
}

private struct FirstInsightReveal: View {
    let insight: Insight
    let ink: Color

    var body: some View {
        VStack(spacing: 26) {
            Text("oh.")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.46))

            Text(insight.line)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(ink.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 30)
                .frame(maxWidth: 560)
        }
        .padding(.bottom, 46)
    }
}

#Preview {
    OnboardingView()
        .environment(SpotifyMusicNode())
        .environment(SelfieNode())
        .environment(TasteProfile())
}
