import SwiftUI
import UIKit
import Combine

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
    @Environment(SelfieNode.self) private var selfie
    @Environment(PromptNode.self) private var promptNode
    @Environment(TasteProfile.self) private var profile
    @Environment(NodeProgression.self) private var progression
    @AppStorage private var wormName: String
    @AppStorage("worm.askedNotificationPermission") private var askedNotificationPermission = false
    // The daily delivery time the user picks in the step before the base flow.
    @AppStorage(NodeProgression.hasChosenDeliveryTimeKey) private var hasChosenDeliveryTime = false
    @AppStorage(NodeProgression.deliveryHourKey) private var deliveryHour = 20
    @AppStorage(NodeProgression.deliveryMinuteKey) private var deliveryMinute = 0
    @AppStorage(NodeProgression.deliveryTestDeadlineKey) private var deliveryTestDeadlineRaw: Double = 0
    // The delivery-time wheel's live selection (defaults to 8:00 pm).
    @State private var pickerHour12 = 8
    @State private var pickerMinute = 0
    @State private var pickerIsPM = true
    /// Continuous hour24 the picker reports as it scrolls; drives the live sky and
    /// the adaptive foreground ink. Defaults to the 8:00 pm wheel start.
    @State private var pickerLiveTime: Double = 20
    /// Schedules the recurring daily "he's back with songs" notification.
    @State private var digScheduler = UnlockNotificationScheduler()
    /// Shown only once the worm has crawled in and settled (driven by the
    /// entrance/reveal sequence), never during the crawl.
    /// The post-time-set home flow (journey-off base state): pick a time → explain
    /// + ask for notifications → "done, see you at ___" → the waiting/digging
    /// screen with its "i'll be back in Hh:Mm" countdown. `nil` = not in the flow.
    @State private var deliveryFlow: DeliveryFlowStep?
    /// Owns persisted picks, the deadline, and the backend dig synchronization.
    @State private var digCycle = DigCycleCoordinator()
    /// Shared with `DiggingLogView` — clearing it starts a fresh dig cycle.
    @AppStorage("worm.digStartedAt") private var digStartRaw: Double = 0
    @Environment(\.scenePhase) private var scenePhase
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
    // MARK: Base-apple detail (in-scene expand → blur → copy + buttons)
    /// The base apple currently expanded to center with its detail revealed.
    @State private var expandedEntry: NodeCatalogEntry?
    /// Where the expanded apple started (its tree slot), for the seamless grow.
    @State private var expandedOrigin: CGPoint = .zero
    /// Grown to center. Drives the apple's slot -> center travel.
    @State private var appleExpanded = false
    /// The blur + copy + buttons faded in behind/under the apple.
    @State private var detailRevealed = false
    /// The confirmed apple flying into the worm's mouth.
    @State private var appleEating = false
    /// Fades the flown apple out as it lands in the mouth, so it reads as
    /// swallowed instead of lingering on the worm while `expandedEntry` is held.
    @State private var appleSwallowed = false
    /// The current valid self-report answer in the detail (nil = incomplete).
    @State private var detailAnswer: PromptCaptureValue?
    /// The "foundation complete" moment after the last base apple: explains the
    /// daily drip, asks for notifications, then reveals the countdown.
    @State private var baseCompleteVisible = false
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
    /// The intro (forest build + worm crawl) plays once per session. After that,
    /// re-appearing (e.g. popping back from profile) restores the settled scene.
    @State private var hasPlayedEntrance = false
    @State private var homeControlsVisible: Bool
    @State private var forestBuildTask: Task<Void, Never>?
    @State private var showHiddenProfile = false

    private enum MorselPhase { case offscreen, hovering, fed, gone }
    private enum NamingStep { case intro, entry }
    private enum DeliveryFlowStep { case picker, notify, done, waiting, arrived }

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
        let name = UserDefaults.standard.string(forKey: wormNameKey) ?? ""
        let hasNamedWorm = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasChosenDelivery = UserDefaults.standard.bool(forKey: NodeProgression.hasChosenDeliveryTimeKey)
        // Resolve an already-running dig before `body` first evaluates. Waiting
        // until `onAppear` lets the home worm and its tag render for one frame.
        _deliveryFlow = State(initialValue:
            !DevFlags.dailyFoodJourneyEnabled && hasNamedWorm && hasChosenDelivery ? .waiting : nil
        )
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

                if DevFlags.sceneEnabled {
                    ForestHomeBackdrop(buildProgress: forestBuildProgress)
                        .ignoresSafeArea()
                }

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
                    // Stay sharp above the detail blur when an apple is expanded.
                    .zIndex((expandedEntry != nil || baseCompleteVisible || isDeliveryFlowActive) ? 4 : 0)
                    // On the waiting screen the worm is away digging — he's gone,
                    // the log terminal takes the screen.
                    .opacity(isWaiting ? 0 : 1)
                    .allowsHitTesting(!isWaiting)
                    .animation(.easeInOut(duration: 0.5), value: isWaiting)

                    // The living digging log — the waiting-screen background.
                    if isWaiting {
                        DiggingLogView(deliveryHour: deliveryHour, deliveryMinute: deliveryMinute)
                            .transition(.opacity)
                            .zIndex(2)
                    }

                    if DevFlags.sceneEnabled {
                        ForestHomeForeground(buildProgress: forestBuildProgress)
                            .ignoresSafeArea()
                    }

                    if nameTagVisible,
                       let displayName = wormDisplayName,
                       !isWaiting,
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
                        .zIndex((expandedEntry != nil || baseCompleteVisible || isDeliveryFlowActive) ? 4 : 1)
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
                    // fed in a fixed order — only the first un-fed apple is live,
                    // each unlocking the next; no countdown until the last one lands.
                    if DevFlags.dailyFoodJourneyEnabled,
                       progression.isBasePhase, !isNamingFlowActive, hasChosenDeliveryTime {
                        ForEach(progression.pendingBaseEntries) { entry in
                            if entry.id != consumingBaseID, entry.id != expandedEntry?.id,
                               revealedBaseIDs.contains(entry.id) {
                                let slot = baseApplePosition(for: entry, in: viewport)
                                // Sequenced: only the first un-fed apple is live;
                                // the rest wait, greyed, each unlocking the next.
                                let isActive = entry.id == activeBaseEntryID
                                let appleSize: CGFloat = 92
                                // One motion only: the apple floats. The number and
                                // the label stay put, so nothing fights it.
                                ZStack {
                                    FeedMorselView(entry: entry, ink: ink, paper: paper, size: appleSize)
                                        .shadow(color: Color(red: 0.98, green: 0.55, blue: 0.28)
                                            .opacity(isActive ? 0.5 : 0), radius: isActive ? 18 : 0)
                                        .modifier(HoverBob(active: isActive))

                                    BaseStepBadge(number: baseStepNumber(for: entry), ink: ink)
                                        .offset(x: -(appleSize / 2 + 13))

                                    BaseAppleTag(title: entry.title, ink: ink, paper: paper)
                                        .offset(y: appleSize / 2 + 16)
                                }
                                .opacity(isActive ? 1 : 0.4)
                                .modifier(RevealPop(isActive: isActive))
                                .animation(.easeOut(duration: 0.45), value: isActive)
                                .contentShape(Rectangle())
                                .position(slot)
                                .allowsHitTesting(isActive && expandedEntry == nil)
                                .onTapGesture { openBaseDetail(entry, at: slot) }
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                            }
                        }
                    }

                    // Base-apple detail: tap → the apple grows to center, a blur
                    // fades in over the scene (behind worm/nametag/apple), then the
                    // copy + buttons + X reveal.
                    if let entry = expandedEntry {
                        let big: CGFloat = 152
                        let center = CGPoint(x: W / 2, y: H * 0.20)
                        let appleScale: CGFloat = appleEating ? 0.16 : (appleExpanded ? 1 : 92 / big)
                        let applePos = appleEating ? feedPoint : (appleExpanded ? center : expandedOrigin)

                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()
                            .opacity(detailRevealed ? 1 : 0)
                            .contentShape(Rectangle())
                            .onTapGesture { closeBaseDetail() }
                            .zIndex(3)

                        FoodAppleView(entry: entry, size: big, emblemSize: 34, ink: ink, paper: paper)
                            .scaleEffect(appleScale)
                            .position(applePos)
                            .opacity(appleSwallowed ? 0 : 1)
                            .zIndex(5)
                            .allowsHitTesting(false)

                        if detailRevealed, !appleEating {
                            let hasPreview: Bool = {
                                if case .photo = detailAnswer { return true }
                                return false
                            }()

                            // Title + subtitle ride high, just under the apple.
                            baseDetailHeader(for: entry, showSubtitle: !hasPreview)
                                .frame(maxWidth: 320)
                                .position(x: W / 2, y: H * 0.33)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                                .zIndex(5)

                            // Content (preview / input) centered in the gap between
                            // the subtitle and the worm.
                            baseDetailContent(for: entry)
                                .frame(maxWidth: 320)
                                .position(x: W / 2, y: H * 0.53 - keyboardHeight * 0.5)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                                .zIndex(5)

                            // The CTA sits low, matching the X's small inset up top;
                            // it lifts above the keyboard when typing a text answer.
                            baseDetailCTA(for: entry)
                                .frame(maxWidth: 300)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .padding(.bottom, 14)
                                .offset(y: -keyboardHeight)
                                .zIndex(6)

                            Button { closeBaseDetail() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ink.opacity(0.55))
                                    .frame(width: 44, height: 44)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .position(x: 42, y: 40)
                            .transition(.opacity)
                            .zIndex(6)
                        }
                    }

                    // Foundation complete: the end-of-onboarding moment. Blur the
                    // scene (worm stays sharp), explain the daily drip, ask for
                    // notifications in context, then reveal the countdown.
                    if baseCompleteVisible {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .zIndex(3)

                        VStack(spacing: 14) {
                            Text("he's got his foundation")
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(ink)
                            Text("from here, \(wormDisplayName ?? "he") gets hungry once a day — a new thing to feed him, and he reads you a little sharper each time.")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(ink.opacity(0.6))
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .position(x: W / 2, y: H * 0.30)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .zIndex(5)

                        VStack(spacing: 12) {
                            Text("want a nudge when he's hungry?")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(ink.opacity(0.5))
                            Button {
                                Haptics.success()
                                enableNotificationsThenFinish()
                            } label: {
                                Text("notify me")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(paper)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(ink, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            Button {
                                Haptics.impact(.light)
                                askedNotificationPermission = true
                                finishFoundation()
                            } label: {
                                Text("not now")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(ink.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: 300)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 14)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .zIndex(6)
                    }

                    // The delivery flow's living sky sits behind every step — the
                    // picker, the notification ask, the "done" beat, and (for now)
                    // the waiting screen. Its color + the sun/moon track the chosen
                    // time; the worm and copy read as UI in front of it.
                    if showDeliveryBackdrop {
                        DeliveryTimeBackdrop(time: pickerLiveTime)
                            .transition(.opacity)
                            .zIndex(3)
                    }

                    // Step 1 — the time wheel.
                    if deliveryFlow == .picker {
                        DeliveryTimePicker(
                            wormName: wormDisplayName ?? "your worm",
                            hour12: $pickerHour12,
                            minute: $pickerMinute,
                            isPM: $pickerIsPM,
                            onLiveTime: { pickerLiveTime = $0 }
                        )
                        .frame(maxWidth: 340)
                        .position(x: W / 2, y: H * 0.24)
                        .transition(.opacity)
                        .zIndex(5)

                        Button {
                            confirmDeliveryTime()
                        } label: {
                            Text("that's it")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(DeliveryTimeBackdrop.onForeground(at: pickerLiveTime))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(DeliveryTimeBackdrop.foreground(at: pickerLiveTime), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 300)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                        .zIndex(6)
                        .animation(.easeInOut(duration: 0.3), value: pickerLiveTime)
                    }

                    // Step 2 — explain, then ask for notifications in context.
                    if deliveryFlow == .notify {
                        deliveryInterstitialCopy(
                            title: "want a nudge when I'm done?",
                            body: "I'll be digging to find you music until \(deliveryClockString).",
                            at: CGPoint(x: W / 2, y: H * 0.30)
                        )
                        .zIndex(5)

                        VStack(spacing: 12) {
                            filledCTA("notify me") {
                                Haptics.success()
                                notifyThenContinue()
                            }
                            Button {
                                Haptics.impact(.light)
                                skipNotify()
                            } label: {
                                Text("not now")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(DeliveryTimeBackdrop.foreground(at: pickerLiveTime).opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: 300)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                        .zIndex(6)
                    }

                    // Step 3 — "done. see you at ___", then it eases into waiting.
                    if deliveryFlow == .done {
                        deliveryInterstitialCopy(
                            title: "done.",
                            body: "see you at \(deliveryClockString)",
                            at: CGPoint(x: W / 2, y: H * 0.30)
                        )
                        .zIndex(5)
                    }

                    // Dig complete — the worm's home with what he found.
                    if deliveryFlow == .arrived {
                        VStack(spacing: 18) {
                            VStack(spacing: 6) {
                                Text("\(wormDisplayName ?? "he")'s back")
                                    .font(.system(size: 30, weight: .bold, design: .serif))
                                    .foregroundStyle(ink)
                                Text("dug you up 3 songs")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(ink.opacity(0.6))
                            }
                            VStack(spacing: 8) {
                                ForEach(Array(foundSongs.enumerated()), id: \.offset) { _, song in
                                    HStack(spacing: 12) {
                                        songArtwork(song)
                                            .frame(width: 46, height: 46)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ink.opacity(0.1)))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(song.title)
                                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                                .foregroundStyle(ink)
                                                .lineLimit(1)
                                            Text(song.artist)
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundStyle(ink.opacity(0.55))
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.opacity(0.05)))
                                }
                            }
                            .frame(maxWidth: 300)
                        }
                        .frame(maxWidth: 340)
                        .position(x: W / 2, y: H * 0.34)
                        .transition(.opacity)
                        .zIndex(5)

                        filledCTA("see you tomorrow") { continueAfterArrival() }
                            .frame(maxWidth: 300)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 14)
                            .transition(.opacity)
                            .zIndex(6)
                    }

                    if DevFlags.dailyFoodJourneyEnabled,
                       !isNamingFlowActive, let morsel, morselPhase == .hovering || morselPhase == .fed {
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
            if isWaiting, homeControlsVisible {
                waitingHeader
                    .offset(y: 100)
                    .transition(.opacity)
            } else if DevFlags.dailyFoodJourneyEnabled,
               !isNamingFlowActive, !namingHandoffVisible, homeControlsVisible {
                Group {
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
                // Rises back with weight once the detail closes / an apple is fed —
                // independent of the apple, so closing never re-pops it. Hidden
                // through the foundation-complete moment too.
                .opacity(homeChromeVisible ? 1 : 0)
                .offset(y: homeChromeVisible ? 0 : 18)
                .animation(.spring(response: 0.7, dampingFraction: 0.72), value: homeChromeVisible)
                .allowsHitTesting(homeChromeVisible)
            }
        }
        .overlay(alignment: .topTrailing) {
            if homeControlsVisible, !isNamingFlowActive, !namingHandoffVisible {
                // Intentionally invisible: double-tap the top-right corner to open
                // the profile without adding chrome to the forest or waiting log.
                Color.clear
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        showHiddenProfile = true
                    }
                    .accessibilityHidden(true)
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
        .onReceive(NotificationCenter.default.publisher(for: .wormForceReveal)) { _ in
            forceRevealTodayNow()
        }
        // On entering the waiting screen: pin the cycle start + deadline, restore any
        // finished dig, and kick the real recommendation query off in the background
        // so its picks are ready to reveal when the timer completes.
        .onChange(of: deliveryFlow) { _, step in
            if step == .waiting {
                beginDigCycle()
            }
        }
        .onChange(of: deliveryTestDeadlineRaw) { _, deadline in
            guard deadline > 0 else { return }
            digStartRaw = Date().timeIntervalSinceReferenceDate
            withAnimation(.easeInOut(duration: 0.3)) { deliveryFlow = .waiting }
            beginDigCycle()
        }
        // Self-heal: on foreground, re-pull the upcoming batch so a long-open app
        // still picks up the next day's slot without a relaunch.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, deliveryFlow == .waiting { syncFromBackend() }
        }
        // Tick: when the countdown reaches the reveal moment, arrive (the batch is
        // already cached locally, so the reveal needs no network).
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if deliveryFlow == .waiting, let deadline = digCycle.deadline, Date() >= deadline { arriveHome() }
        }
        .navigationDestination(isPresented: $showHiddenProfile) {
            ProfileView()
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

            Text("hi \(name).")
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

    // MARK: - Delivery flow UI

    /// The waiting-screen top header: "i'll be back in Hh:Mm", counting down to the
    /// next daily visit. Ticks each second; colors adapt to the sky behind it.
    private var waitingHeader: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 4) {
                Text("I'll be back in")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ink.opacity(0.8))
                Text(timeUntilDeliveryString)
                    .font(.system(size: 46, weight: .heavy, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(ink)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            // A soft paper cushion (blurred, no hard edge) so the copy reads cleanly
            // over the running log beneath it.
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(paper)
                    .blur(radius: 14)
                    .padding(4)
            }
        }
    }

    /// A centered title + body for the notification-ask and "done" interstitials,
    /// in the same adaptive ink as the rest of the delivery flow.
    private func deliveryInterstitialCopy(title: String, body: String, at point: CGPoint) -> some View {
        let fg = DeliveryTimeBackdrop.foreground(at: pickerLiveTime)
        let halo = DeliveryTimeBackdrop.onForeground(at: pickerLiveTime)
        return VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(fg)
                .shadow(color: halo.opacity(0.45), radius: 5)
            Text(body)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(fg.opacity(0.82))
                .shadow(color: halo.opacity(0.4), radius: 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
        .position(point)
        .transition(.opacity)
    }

    /// The shared filled pill CTA used in the delivery flow (adaptive fill + label).
    private func filledCTA(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(DeliveryTimeBackdrop.onForeground(at: pickerLiveTime))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(DeliveryTimeBackdrop.foreground(at: pickerLiveTime), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Base phase

    /// The stacked line shown up top during the base phase, in place of the
    /// countdown. Big and inviting: build the worm a foundation before the drip.
    private var baseEncouragement: some View {
        let remaining = progression.pendingBaseEntries.count
        return VStack(spacing: 4) {
            Text("let \(wormDisplayName ?? "him")")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(ink.opacity(0.85))
            Text("get to know you")
                .font(.system(size: 34, weight: .semibold, design: .serif))
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
        case 1: "one more, then he starts to get you"
        case 2: "give him a few things to go on"
        default: "the more he sees,\n the better he knows you"
        }
    }

    /// The one base apple that's currently live: the first in the fixed base
    /// order that hasn't been fed yet. Feeding it advances the sequence.
    private var activeBaseEntryID: String? {
        progression.pendingBaseEntries.first?.id
    }

    /// The apple's step number (1-based) in the fixed base order, shown in its badge.
    private func baseStepNumber(for entry: NodeCatalogEntry) -> Int {
        (progression.baseEntries.firstIndex(of: entry) ?? 0) + 1
    }

    /// A fixed tree slot per base entry, keyed off its position in the base set so
    /// apples never reshuffle as siblings get eaten. Scattered heights, "in the
    /// trees": upper-left canopy, upper-right canopy, lower-center.
    private func baseApplePosition(for entry: NodeCatalogEntry, in viewport: CGSize) -> CGPoint {
        // Two up top (left/right), one lower-center. Spread wide with room below
        // each for its tag, and the lower one lifted clear of the worm's bed.
        let slots: [(CGFloat, CGFloat)] = [(0.27, 0.43), (0.74, 0.45), (0.50, 0.60)]
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

        // The dig is already in progress: the log owns the first visible frame.
        // Do not begin the forest/worm entrance behind it, even transiently.
        if isWaiting {
            forestBuildProgress = 1
            homeControlsVisible = true
            entranceStart = nil
            nameTagVisible = false
            beginDigCycle()
            return
        }

        // Second and later appearances this session (popping back from profile or
        // a node detail): the scene is already established. Snap it to its settled
        // state — worm resting, food/copy already present — with no replay.
        guard !hasPlayedEntrance else {
            restoreSettledScene()
            return
        }
        hasPlayedEntrance = true

        // Forest already painted (e.g. the replay demo): skip the build, just
        // crawl the worm in.
        guard buildsForestOnEntry else {
            forestBuildProgress = 1
            homeControlsVisible = true
            beginEntrance()
            return
        }

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

    /// Re-entry without the intro: park everything in its final resting state so
    /// the worm, food, and copy are simply already there.
    private func restoreSettledScene() {
        forestBuildTask?.cancel()
        forestBuildTask = nil
        forestBuildProgress = 1
        homeControlsVisible = true
        digestCaption = nil
        wormWiggles = []
        consumingBaseID = nil
        morselOrigin = nil
        gulpStart = nil
        fromSize = earnedSize
        toSize = earnedSize

        // Place the entrance clock far enough in the past that the worm renders
        // fully settled at its resting spot, no crawl.
        let settledAgo = wormEntranceDelay + wormEntranceDuration + wormEntranceSettleDuration + 1
        entranceStart = Date().timeIntervalSinceReferenceDate - settledAgo

        // Getting here means naming is done (profile is unreachable during it).
        resetNamingFlowIfNeeded()
        nameTagVisible = wormDisplayName != nil

        // Journey gated off: the base state is the waiting/digging screen (if a
        // time's been set), otherwise nothing yet.
        guard DevFlags.dailyFoodJourneyEnabled else {
            morsel = nil
            morselPhase = .offscreen
            revealedBaseIDs = []
            if hasChosenDeliveryTime {
                pickerLiveTime = deliveryTimeAsHours
                ensureDailyDigScheduled()   // keep the daily nudge armed on launch
                deliveryFlow = .waiting
            } else {
                deliveryFlow = nil
            }
            return
        }

        if progression.isBasePhase {
            morsel = nil
            morselPhase = .offscreen
            revealedBaseIDs = Set(progression.pendingBaseEntries.map(\.id))
        } else {
            revealedBaseIDs = []
            if let next = nextMorsel {
                morsel = next
                morselFlight = 0
                morselPhase = .hovering
            } else {
                morsel = nil
                morselPhase = .offscreen
            }
        }
    }

    // The worm crawls in once, on the first entry this session.

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
        deliveryFlow = nil
        resetNamingFlowIfNeeded()

        // Already set up and waiting (journey off, time chosen, named): the worm is
        // out digging, so skip the crawl and drop straight into the waiting log.
        if !DevFlags.dailyFoodJourneyEnabled, hasChosenDeliveryTime, hasWormName {
            let settledAgo = wormEntranceDelay + wormEntranceDuration + wormEntranceSettleDuration + 1
            entranceStart = Date().timeIntervalSinceReferenceDate - settledAgo
            pickerLiveTime = deliveryTimeAsHours
            ensureDailyDigScheduled()
            withAnimation(.easeInOut(duration: 0.5)) { deliveryFlow = .waiting }
            return
        }

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
    /// phase offers: the delivery-time picker, the waiting screen, the scattered
    /// base apples, or the single drip morsel.
    private func revealFoodForCurrentPhase() async {
        // First run: no delivery time yet — the worm has settled, now raise the
        // time-of-day step.
        if !hasChosenDeliveryTime {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.45)) { deliveryFlow = .picker }
            }
            return
        }
        // Journey gated off: the base state is the waiting/digging screen, with the
        // sky frozen at the chosen time.
        guard DevFlags.dailyFoodJourneyEnabled else {
            await MainActor.run {
                pickerLiveTime = deliveryTimeAsHours
                ensureDailyDigScheduled()   // keep the daily nudge armed on launch
                withAnimation(.easeInOut(duration: 0.55)) { deliveryFlow = .waiting }
            }
            return
        }
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

    /// The top header + profile button are visible only in the plain home state —
    /// hidden while an apple detail, the delivery-time step, or the
    /// foundation-complete moment is up.
    private var homeChromeVisible: Bool {
        expandedEntry == nil
            && !baseCompleteVisible
            && !isDeliveryInterstitial
            && deliveryFlow != .arrived
            // In the base phase the header/profile only belong to the base flow,
            // which starts AFTER the delivery-time step — never before it.
            && (!progression.isBasePhase || hasChosenDeliveryTime)
    }

    /// The time-of-day sky sits behind the picker/notify/done steps only (and only
    /// when the scene is enabled). It crossfades out as we cross into the waiting
    /// screen (which is plain paper under the living digging background instead).
    private var showDeliveryBackdrop: Bool {
        DevFlags.deliveryTimeSceneEnabled && isDeliveryInterstitial
    }

    /// Any step of the delivery flow is active (keeps the worm sharp in front).
    private var isDeliveryFlowActive: Bool { deliveryFlow != nil }

    /// The full-screen interstitials that take over the scene (chrome hidden).
    private var isDeliveryInterstitial: Bool {
        deliveryFlow == .picker || deliveryFlow == .notify || deliveryFlow == .done
    }

    /// The base state: worm home, waiting for the next daily visit.
    private var isWaiting: Bool { deliveryFlow == .waiting }

    private var pickerHour24: Int {
        let base = pickerHour12 % 12
        return pickerIsPM ? base + 12 : base
    }

    /// Save the chosen delivery time, then move into the contextual notification
    /// ask (journey off) or the base-apple flow (journey on).
    private func confirmDeliveryTime() {
        deliveryHour = pickerHour24
        deliveryMinute = pickerMinute
        Haptics.success()
        hasChosenDeliveryTime = true

        guard DevFlags.dailyFoodJourneyEnabled else {
            // Arm the recurring daily notification for the chosen time now; the
            // permission prompt comes next in the .notify step.
            ensureDailyDigScheduled()
            // The time is set: this is the natural moment to explain the daily
            // visit and ask for a nudge. Notifications only make sense now.
            withAnimation(.easeInOut(duration: 0.45)) { deliveryFlow = .notify }
            return
        }

        withAnimation(.easeInOut(duration: 0.45)) { deliveryFlow = nil }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            await revealFoodForCurrentPhase()   // now pops the base apples in
        }
    }

    /// "notify me": request permission in context, then land the "done" beat.
    private func notifyThenContinue() {
        askedNotificationPermission = true
        Task {
            await progression.requestNotificationPermission()
            await MainActor.run { goToDoneThenWaiting() }
        }
    }

    /// "not now": no permission prompt, straight to the "done" beat.
    private func skipNotify() {
        askedNotificationPermission = true
        goToDoneThenWaiting()
    }

    /// Show "done. see you at ___" for a beat, then ease into the waiting screen.
    private func goToDoneThenWaiting() {
        withAnimation(.easeInOut(duration: 0.4)) { deliveryFlow = .done }
        Task {
            try? await Task.sleep(for: .seconds(2.0))
            await MainActor.run {
                pickerLiveTime = deliveryTimeAsHours
                withAnimation(.easeInOut(duration: 0.7)) { deliveryFlow = .waiting }
            }
        }
    }

    /// The clock hit the reveal moment. The worm comes home and shows the batch
    /// that was already dug (a day ahead) and cached locally. Records which reveal
    /// date was shown so we don't replay it after "continue".
    private func arriveHome() {
        guard deliveryFlow == .waiting else { return }
        digCycle.markRevealed()
        Haptics.success()
        withAnimation(.easeInOut(duration: 0.7)) { deliveryFlow = .arrived }
    }

    /// Dismiss the reveal and wait for the next slot: clear the shown batch + test
    /// deadline, count down to the next delivery, and re-sync (the server fills the
    /// next day's slot right after this delivery time).
    private func continueAfterArrival() {
        Haptics.impact(.medium)
        deliveryTestDeadlineRaw = 0
        digStartRaw = 0
        digCycle.reset(input: digCycleInput, testDeadline: 0)
        ensureDailyDigScheduled()
        withAnimation(.easeInOut(duration: 0.6)) { deliveryFlow = .waiting }
    }

    /// The three songs to reveal: the cached upcoming picks (with exact covers) once
    /// they've landed, otherwise placeholders until the fetch finishes.
    private var foundSongs: [FoundSong] {
        if !digCycle.recommendations.isEmpty { return Array(digCycle.recommendations.prefix(3)) }
        return DiggingLog.finds(seed: UInt64(bitPattern: Int64(max(0, digStartRaw).rounded())))
            .map { FoundSong(title: $0.title, artist: $0.artist, artwork: nil) }
    }

    /// The exact album cover for a pick, or a music-note placeholder when none was
    /// resolved (never a mismatched image).
    @ViewBuilder
    private func songArtwork(_ song: FoundSong) -> some View {
        if let s = song.artwork, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Rectangle().fill(ink.opacity(0.06))
            Image(systemName: "music.note")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink.opacity(0.4))
        }
    }

    // MARK: - Recommendation dig boundary

    private var digCycleInput: DigCycleSyncInput {
        let context = brainInputs.context(read: profile.read, insights: profile.insights)
        let textSlices = context.populatedSlices
            .filter { !$0.summary.isEmpty }
            .map { WormAPI.TextSlice(node: $0.nodeID.rawValue, summary: $0.summary) }
        return DigCycleSyncInput(
            deliveryHour: deliveryHour,
            deliveryMinute: deliveryMinute,
            wormName: wormDisplayName,
            nodes: buildWormNodes(),
            textSlices: textSlices,
            spotifyRefreshToken: spotify.currentRefreshToken
        )
    }

    private func syncFromBackend() {
        guard !DevFlags.dailyFoodJourneyEnabled, hasChosenDeliveryTime else { return }
        let input = digCycleInput
        let testDeadline = deliveryTestDeadlineRaw
        Task {
            if await digCycle.sync(input: input, testDeadline: testDeadline), deliveryFlow == .waiting {
                arriveHome()
            }
        }
    }

    private func beginDigCycle() {
        guard !DevFlags.dailyFoodJourneyEnabled, hasChosenDeliveryTime else { return }
        if digStartRaw == 0 { digStartRaw = Date().timeIntervalSinceReferenceDate }
        digCycle.beginWaiting(input: digCycleInput, testDeadline: deliveryTestDeadlineRaw)
        syncFromBackend()
    }

    private func forceRevealTodayNow() {
        let input = digCycleInput
        Task {
            await digCycle.forceReveal(input: input)
            Haptics.success()
            withAnimation(.easeInOut(duration: 0.6)) { deliveryFlow = .arrived }
        }
    }

    /// Arm (or re-arm) the recurring daily "he's back with songs" notification at
    /// the chosen delivery time. Journey-off waiting flow only — the journey path
    /// has its own unlock notifications. Safe to call repeatedly (stable id).
    private func ensureDailyDigScheduled() {
        guard !DevFlags.dailyFoodJourneyEnabled, hasChosenDeliveryTime else { return }
        digScheduler.scheduleDailyDig(
            hour: deliveryHour,
            minute: deliveryMinute,
            wormName: wormDisplayName ?? "your worm"
        )
    }

    /// The one-time "when should he bring you songs?" step. It's raised by the
    /// entrance/reveal sequence (after the crawl + settle), so it never appears
    /// mid-crawl; the flag alone gates the overlay/chrome/z-order.
    /// The chosen delivery time, formatted for copy ("8:00 pm").
    private var deliveryClockString: String {
        let isPM = deliveryHour >= 12
        var h12 = deliveryHour % 12
        if h12 == 0 { h12 = 12 }
        return String(format: "%d:%02d %@", h12, deliveryMinute, isPM ? "pm" : "am")
    }

    /// The chosen delivery time as a continuous hour (0..24), for the sky.
    private var deliveryTimeAsHours: Double {
        Double(deliveryHour) + Double(deliveryMinute) / 60
    }

    /// The coordinator owns deadline resolution and display formatting.
    private var timeUntilDeliveryString: String {
        digCycle.formattedRemaining()
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

    // MARK: - Base-apple detail flow

    /// Tap a base apple: haptic, then grow it to center and, once it lands, fade
    /// in the blur and reveal its copy + buttons. Replaces the old capture sheet.
    private func openBaseDetail(_ entry: NodeCatalogEntry, at slot: CGPoint) {
        guard expandedEntry == nil, consumingBaseID == nil else { return }
        Haptics.impact(.medium)
        expandedOrigin = slot
        appleExpanded = false
        detailRevealed = false
        appleEating = false
        appleSwallowed = false
        detailAnswer = nil
        expandedEntry = entry
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { appleExpanded = true }
        Task {
            try? await Task.sleep(for: .seconds(0.42))
            await MainActor.run {
                // A springy reveal so the copy + button pop in, not slide.
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { detailRevealed = true }
            }
        }
    }

    /// Title + subtitle for the expanded detail (subtitle hidden once a photo
    /// preview is carrying the meaning).
    @ViewBuilder
    private func baseDetailHeader(for entry: NodeCatalogEntry, showSubtitle: Bool) -> some View {
        VStack(spacing: 8) {
            Text(entry.title)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            if showSubtitle {
                Text(entry.resolvedSubtitle(wormName: wormDisplayName))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.6))
            }
        }
        .multilineTextAlignment(.center)
    }

    /// The middle content of the expanded detail: a photo preview once picked, or
    /// the self-report input for text/choice. Source apples have none.
    @ViewBuilder
    private func baseDetailContent(for entry: NodeCatalogEntry) -> some View {
        switch entry.captureKind {
        case .photo:
            if case .photo(let img) = detailAnswer {
                // scaledToFit + height-cap keeps the real aspect (a lock screen
                // stays a tall card) with no letterbox side-margins.
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ink.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            }
        case .text, .choice:
            PromptInputSection(entry: entry, ink: ink, paper: paper, answer: $detailAnswer)
        case .source:
            EmptyView()
        }
    }

    /// The confirm button for the expanded detail, shown below the worm.
    @ViewBuilder
    private func baseDetailCTA(for entry: NodeCatalogEntry) -> some View {
        switch entry.captureKind {
        case .source:
            Button {
                Haptics.success()
                confirmBaseSource(entry)
            } label: {
                Text("let him in")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(ink, in: Capsule())
            }
            .buttonStyle(.plain)
        case .photo:
            // pick a photo → (done + pick another), all below the worm.
            BasePhotoActions(ink: ink, paper: paper, answer: $detailAnswer) {
                if let detailAnswer { confirmBasePrompt(entry, detailAnswer) }
            }
        case .text, .choice:
            PromptDoneButton(enabled: detailAnswer != nil, ink: ink, paper: paper) {
                if let detailAnswer { confirmBasePrompt(entry, detailAnswer) }
            }
        }
    }

    /// X / tap-outside: reverse it — copy fades, apple shrinks back to its slot.
    private func closeBaseDetail() {
        guard expandedEntry != nil, !appleEating else { return }
        Haptics.impact(.light)
        // Copy + CTA pop out; the apple shrinks back to its slot.
        withAnimation(.easeIn(duration: 0.22)) { detailRevealed = false }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appleExpanded = false }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            await MainActor.run {
                // Clear WITHOUT an animation so the base apple doesn't "reload"
                // (re-insert with its pop transition) — the shrunk expanded apple
                // was already sitting exactly in its slot, so the swap is seamless.
                // The header + profile fade back on their own opacity animation.
                expandedEntry = nil
            }
        }
    }

    /// Prompt answered in the detail: record it, then eat.
    private func confirmBasePrompt(_ entry: NodeCatalogEntry, _ value: PromptCaptureValue) {
        switch value {
        case .text(let str): promptNode.record(entryID: entry.id, title: entry.title, answer: str)
        case .photo: promptNode.recordPhoto(entryID: entry.id, title: entry.title, visionKeywords: [])
        }
        eatExpanded(entry)
    }

    /// Source "let him in": authorize (sync runs in the background), then eat.
    /// Denied → just close, no claim.
    private func confirmBaseSource(_ entry: NodeCatalogEntry) {
        Task {
            let granted = await connectNode(for: entry.sourceRoute)
            await MainActor.run {
                if granted { eatExpanded(entry) } else { closeBaseDetail() }
            }
        }
    }

    /// The confirmed apple flies into the worm and he swallows + grows; then, as a
    /// first-run beat, the scene un-blurs, the "eating ..." line sits for a moment,
    /// and finally the home flow returns with weight — the next step pops in and the
    /// "let ___ get to know you" header rises back. Deliberately unhurried.
    private func eatExpanded(_ entry: NodeCatalogEntry) {
        // The last base apple? Then this eat rolls into the finish moment, not
        // back to the base flow.
        let isLastBase = progression.pendingBaseEntries.map(\.id) == [entry.id]
        withAnimation(.easeIn(duration: 0.25)) { detailRevealed = false }   // copy/CTA out, blur fades
        appleSwallowed = false
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.62)) { appleEating = true }  // apple into the mouth
        // Snuff the apple out just as it reaches the mouth so it's gone by the
        // time the worm gulps — no lingering morsel over him during the hold.
        withAnimation(.easeIn(duration: 0.16).delay(0.46)) { appleSwallowed = true }
        // The "eating your camera roll" line settles in under the worm.
        withAnimation(.easeIn(duration: 0.4)) { digestCaption = "eating \(entry.eatingNoun)" }
        Task {
            await settleGrow()                       // he swallows and grows a notch
            await MainActor.run { Haptics.success() }

            // Hold on the digest beat — first-run, let the moment land before we
            // snap back to the flow. `expandedEntry` stays set so the eaten apple
            // doesn't flash back into its tree slot during the pause.
            try? await Task.sleep(for: .seconds(1.5))

            await MainActor.run {
                Haptics.impact(.medium)
                // The return, with weight: claim, and either reveal the next step
                // (RevealPop + header rise) or, if this was the last, roll straight
                // into the "foundation complete" moment.
                withAnimation(.spring(response: 0.8, dampingFraction: 0.68)) {
                    finishBaseUnlock(entry)
                    expandedEntry = nil
                    if isLastBase { baseCompleteVisible = true }
                }
                appleExpanded = false
                appleEating = false
                appleSwallowed = false
                detailRevealed = false
                // The freshly fed node now contributes to the brain.
                ingestBrainSlices()
            }

            // The "eating ..." line lingers a touch past the return, then clears.
            try? await Task.sleep(for: .seconds(1.3))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.6)) { digestCaption = nil }
            }
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
            withAnimation(.easeIn(duration: 0.5)) { digestCaption = "eating \(entry.eatingNoun)" }
        }
        if await connectNode(for: entry.sourceRoute) {
            // Let the "eating…" beat read for a moment (the sync is already
            // running in the background), then move on.
            try? await Task.sleep(for: .seconds(1.6))
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

        // Base done. Don't arm the countdown or ask for notifications yet — that's
        // the "foundation complete" moment (`baseCompleteVisible`), which explains
        // the daily drip, asks permission in context, then reveals the countdown.
        revealedBaseIDs = []
    }

    /// Proceed past the completion moment: arm the first countdown (so the header
    /// slides in with a live clock) and dismiss the interstitial.
    private func finishFoundation() {
        withAnimation(.easeInOut(duration: 0.45)) { baseCompleteVisible = false }
        progression.advance()
        // The foundation is set: read the whole profile (all three nodes), not
        // just one source, so the brain forms its first cross-node understanding.
        ingestBrainSlices()
        synthesizeWholeProfile()
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            await presentNextMorsel()   // no-op while the fresh countdown runs
        }
    }

    /// "notify me": ask in context, then reveal the countdown either way.
    private func enableNotificationsThenFinish() {
        askedNotificationPermission = true
        Task {
            await progression.requestNotificationPermission()
            await MainActor.run { finishFoundation() }
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
            withAnimation(.easeIn(duration: 0.5)) { digestCaption = "eating \(entry.eatingNoun)" }
        }
        if await connectNode(for: entry.sourceRoute) {
            // Let the "eating…" beat read for a moment (the sync is already
            // running in the background), then move on.
            try? await Task.sleep(for: .seconds(1.6))
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

    /// Authorize the source node matching this route, then kick off its sync in
    /// the background. Returns whether it ended up authorized — authorization is
    /// the only gate on "fed". Crucially this awaits `requestAccess()` (the
    /// permission prompt) only, NOT the node's `connect()` (which also awaits the
    /// full `syncEverything()`). The heavy data pull runs in the background via
    /// `startBackgroundSync` so the eating beat is short and the user can feed
    /// the next apple immediately while this node fills in.
    private func connectNode(for route: NodeRoute?) async -> Bool {
        switch route {
        case .appleMusic:
            guard await appleMusic.requestAccess() else { return false }
            startBackgroundSync { await appleMusic.syncEverything() }
            return true
        case .youtube:
            guard await youtube.requestAccess() else { return false }
            startBackgroundSync { await youtube.syncEverything() }
            return true
        case .photos:
            guard await photos.requestAccess() else { return false }
            startBackgroundSync { await photos.syncEverything() }
            return true
        case .contacts:
            guard await contacts.requestAccess() else { return false }
            startBackgroundSync { await contacts.syncEverything() }
            return true
        case .calendar:
            guard await calendar.requestAccess() else { return false }
            startBackgroundSync { await calendar.syncEverything() }
            return true
        case .spotify:
            guard await spotify.requestAccess() else { return false }
            startBackgroundSync { await spotify.syncEverything() }
            return true
        default:
            return false
        }
    }

    /// Run a node's full sync without blocking the feed flow. The node managers
    /// live for the app's lifetime (owned by `WormApp`) and persist their own
    /// snapshots, so this fire-and-forget task safely finishes on its own. When
    /// it lands, refresh the brain so the new node's slice shows up live.
    private func startBackgroundSync(_ sync: @escaping () async -> Void) {
        Task {
            await sync()
            await MainActor.run { ingestBrainSlices() }
        }
    }

    // MARK: - Brain

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

    private static let isoFormatter = ISO8601DateFormatter()
    private func iso(_ date: Date?) -> String? { date.map { Self.isoFormatter.string(from: $0) } }

    /// Reduce every connected node to the compact structured facts the server dig
    /// extracts seeds from — the same fields `BrainSeedExtractor` reads on-device.
    /// Only populated nodes are included; sensitive nodes stay device-reduced to
    /// these small fact arrays (raw media never leaves the device). The backend
    /// additionally refreshes the Spotify node itself from the stored token, so
    /// Spotify seeds stay live while every other node comes from here.
    @MainActor
    private func buildWormNodes() -> WormAPI.WormNodesPayload {
        var nodes = WormAPI.WormNodesPayload()

        // Spotify
        let artist = { (a: SpotifyArtist) in WormAPI.ArtistLite(name: a.name, genres: a.genres) }
        let track = { (t: SpotifyTrack) in
            WormAPI.TrackLite(
                name: t.name,
                artist: t.artists.first?.name,
                popularity: t.popularity,
                album: t.album.map { WormAPI.AlbumLite(name: $0.name, releaseDate: $0.releaseDate) }
            )
        }
        if !spotify.topArtistsLong.isEmpty || !spotify.savedAlbums.isEmpty || !spotify.playlists.isEmpty {
            nodes.spotify = WormAPI.SpotifyNodePayload(
                topArtistsShort: spotify.topArtistsShort.map(artist),
                topArtistsMedium: spotify.topArtistsMedium.map(artist),
                topArtistsLong: spotify.topArtistsLong.map(artist),
                topTracksShort: spotify.topTracksShort.map(track),
                topTracksLong: spotify.topTracksLong.map(track),
                savedAlbums: spotify.savedAlbums.map {
                    WormAPI.SavedAlbumLite(album: .init(name: $0.album.name, label: $0.album.label))
                },
                savedTrackCount: spotify.savedTracks.count,
                playlists: spotify.playlists.map(\.name),
                lastSyncedAt: iso(spotify.lastSyncedAt)
            )
        }

        // Apple Music
        if !appleMusic.songs.isEmpty || !appleMusic.artists.isEmpty {
            let mostPlayed = appleMusic.songs
                .filter { ($0.playCount ?? 0) > 0 }
                .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
                .prefix(20)
                .map { WormAPI.MostPlayedLite(artist: $0.artist, playCount: $0.playCount ?? 0) }
            nodes.appleMusic = WormAPI.AppleMusicNodePayload(
                genreNames: Array(appleMusic.songs.flatMap(\.genreNames).prefix(3000)),
                mostPlayed: mostPlayed,
                playlists: appleMusic.playlists.map(\.name),
                artistNames: appleMusic.artists.map(\.name),
                lastSyncedAt: iso(appleMusic.lastSyncedAt)
            )
        }

        // YouTube
        let ytVideos = youtube.likedVideos + Array(youtube.enrichedVideosByID.values)
        let creatorNames = ytVideos.compactMap { $0.snippet?.channelTitle }
        let topicCategories = ytVideos.flatMap { $0.topicDetails?.topicCategories ?? [] }
            + youtube.enrichedChannelsByID.values.flatMap { $0.topicDetails?.topicCategories ?? [] }
        if !creatorNames.isEmpty || !topicCategories.isEmpty {
            nodes.youtube = WormAPI.YouTubeNodePayload(
                creatorNames: Array(creatorNames.prefix(500)),
                topicCategories: Array(topicCategories.prefix(500)),
                lastSyncedAt: iso(youtube.lastSyncedAt)
            )
        }

        // Photos
        if !photos.albums.isEmpty {
            nodes.photos = WormAPI.PhotosNodePayload(
                locationNames: Array(photos.albums.flatMap(\.locationNames).prefix(500)),
                albumTitles: photos.albums.map(\.title),
                lastSyncedAt: iso(photos.lastSyncedAt)
            )
        }

        // Calendar
        let recurring = calendar.events
            .filter { $0.hasRecurrenceRules || !$0.recurrenceRules.isEmpty }
            .map {
                WormAPI.RecurringEventLite(
                    title: $0.title,
                    hour: Calendar.current.component(.hour, from: $0.startDate),
                    isAllDay: $0.isAllDay
                )
            }
        if !recurring.isEmpty {
            nodes.calendar = WormAPI.CalendarNodePayload(recurringEvents: recurring, lastSyncedAt: iso(calendar.lastSyncedAt))
        }

        // Contacts
        let cities = contacts.contacts.flatMap { $0.postalAddresses.map(\.city) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !cities.isEmpty {
            nodes.contacts = WormAPI.ContactsNodePayload(cities: Array(cities.prefix(1000)), lastSyncedAt: iso(contacts.lastSyncedAt))
        }

        // Selfie
        if let analysis = selfie.analysis, !analysis.aesthetics.isEmpty {
            nodes.selfie = WormAPI.SelfieNodePayload(
                aesthetics: analysis.aesthetics,
                confidence: analysis.confidence,
                lastAnalyzedAt: iso(selfie.lastAnalyzedAt)
            )
        }

        return nodes
    }

    /// Reduce every node into brain slices and hand them to the profile, so a
    /// freshly fed node contributes immediately (its slice, and "brain inputs
    /// active") without waiting for the Profile screen to appear.
    private func ingestBrainSlices() {
        profile.ingest(brainInputs.context(read: profile.read, insights: profile.insights).slices)
    }

    /// Read the whole profile — synthesize over every ingested slice (not just
    /// one node). Runs in the background; the brain owns the Claude call.
    private func synthesizeWholeProfile() {
        Task {
            _ = await profile.synthesize(slices: brainInputs.slices())
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
    var size: CGFloat = 62
    /// Held fixed so a bigger apple just shows more apple, not a bigger emblem.
    var emblemSize: CGFloat = 26

    var body: some View {
        FoodAppleView(entry: entry, size: size, emblemSize: emblemSize, ink: ink, paper: paper)
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

/// The one-time daily-delivery-time step: an iOS-alarm-style wheel, rebuilt in
/// our paper/ink voice (serif numerals, our colors) rather than the raw system
/// picker. Reports back the chosen 24h time.
/// The living sky behind the delivery-time step. Two layers that both track the
/// chosen time continuously (so they fade *while* the wheel spins, not only when
/// it settles): a full-screen sky gradient, and a large sun or moon rising from
/// the bottom — highest at noon/midnight, low on the horizon at dawn/dusk, and
/// crossfading between sun and moon across the transitions.
private struct DeliveryTimeBackdrop: View {
    /// Continuous time-of-day in hours (0..24, includes fractional minutes) so the
    /// sky and the sun/moon track the wheel *while* it scrolls, not only on settle.
    let time: Double

    private var t: Double { time }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Sky: two solid colors (which tween smoothly under the implicit
                // animation) shaped into a vertical gradient by a fixed mask.
                skyBottom
                skyTop.mask(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0),
                                .init(color: .clear, location: 0.9)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                celestial(in: size)
            }
            .animation(.easeInOut(duration: 0.3), value: t)
        }
        .ignoresSafeArea()
    }

    // MARK: - Sky

    private var skyTop: Color { Self.skyGradient(at: t).top }
    private var skyBottom: Color { Self.skyGradient(at: t).bottom }

    /// Keyframed sky palette across the day; linearly interpolated between stops.
    private struct SkyStop {
        let h: Double
        let top: (Double, Double, Double)
        let bottom: (Double, Double, Double)
    }

    private static let skyStops: [SkyStop] = [
        .init(h: 0,    top: (0.043, 0.063, 0.149), bottom: (0.110, 0.137, 0.251)),
        .init(h: 5,    top: (0.141, 0.188, 0.310), bottom: (0.290, 0.290, 0.416)),
        .init(h: 6.5,  top: (0.478, 0.525, 0.722), bottom: (1.000, 0.698, 0.478)),
        .init(h: 9,    top: (0.431, 0.776, 1.000), bottom: (0.804, 0.933, 1.000)),
        .init(h: 12,   top: (0.290, 0.659, 1.000), bottom: (0.749, 0.902, 1.000)),
        .init(h: 15,   top: (0.353, 0.690, 0.961), bottom: (0.812, 0.914, 1.000)),
        .init(h: 18,   top: (0.420, 0.357, 0.584), bottom: (1.000, 0.549, 0.353)),
        .init(h: 20,   top: (0.169, 0.169, 0.322), bottom: (0.420, 0.290, 0.478)),
        .init(h: 22,   top: (0.075, 0.102, 0.220), bottom: (0.141, 0.141, 0.247)),
        .init(h: 24,   top: (0.043, 0.063, 0.149), bottom: (0.110, 0.137, 0.251)),
    ]

    private static func rgbStops(at t: Double) -> (top: (Double, Double, Double), bottom: (Double, Double, Double)) {
        var lo = skyStops[0]
        var hi = skyStops[skyStops.count - 1]
        for i in 0..<(skyStops.count - 1) where t >= skyStops[i].h && t <= skyStops[i + 1].h {
            lo = skyStops[i]; hi = skyStops[i + 1]; break
        }
        let span = hi.h - lo.h
        let f = span > 0 ? (t - lo.h) / span : 0
        return (lerp(lo.top, hi.top, f), lerp(lo.bottom, hi.bottom, f))
    }

    private static func skyGradient(at t: Double) -> (top: Color, bottom: Color) {
        let s = rgbStops(at: t)
        return (color(s.top), color(s.bottom))
    }

    private static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ f: Double) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
    }

    private static func color(_ c: (Double, Double, Double)) -> Color {
        Color(red: c.0, green: c.1, blue: c.2)
    }

    // MARK: - Adaptive UI color

    /// 0 in daylight, 1 at night — read from the sky's luminance, so foreground
    /// UI can stay legible as the backdrop darkens (and update live with it).
    private static func nightFactor(at t: Double) -> Double {
        let top = rgbStops(at: t).top
        let lum = 0.2126 * top.0 + 0.7152 * top.1 + 0.0722 * top.2
        return smoothstep(0.55, 0.30, lum)
    }

    private static let uiDark: (Double, Double, Double) = (0.10, 0.10, 0.13)
    private static let uiLight: (Double, Double, Double) = (0.97, 0.96, 0.90)

    /// The primary UI ink for a time: a *crisp* pick between near-black and cream —
    /// never the muddy mid-gray a linear blend would pass through at dusk/dawn, when
    /// the sky itself is mid-luminance. `onForeground`/the halo cover the crossover.
    /// With the scene off there's no sky, so it's simply ink on paper.
    static func foreground(at t: Double) -> Color {
        guard DevFlags.deliveryTimeSceneEnabled else { return color(uiDark) }
        return color(nightFactor(at: t) >= 0.5 ? uiLight : uiDark)
    }

    /// The contrasting color: sits *on* `foreground` (a button label on a
    /// foreground-filled capsule) and doubles as the legibility halo behind text.
    static func onForeground(at t: Double) -> Color {
        guard DevFlags.deliveryTimeSceneEnabled else { return color(uiLight) }
        return color(nightFactor(at: t) >= 0.5 ? uiDark : uiLight)
    }

    // MARK: - Sun / moon

    /// 1 = full day, 0 = full night, smoothly crossing at dawn (5–7) and dusk (17–19).
    private var sunPresence: Double {
        if t <= 5 || t >= 19 { return 0 }
        if t < 7 { return Self.smoothstep(5, 7, t) }
        if t > 17 { return 1 - Self.smoothstep(17, 19, t) }
        return 1
    }

    private static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func celestial(in size: CGSize) -> some View {
        let R = size.width * 1.05
        // Zenith at noon/midnight (|cos| = 1), grazing the horizon at dawn/dusk.
        let peek = size.height * (0.15 + 0.13 * abs(cos(.pi * t / 12)))
        let centerY = size.height + R - peek
        return ZStack {
            sunBody(radius: R).opacity(sunPresence)
            moonBody(radius: R).opacity(1 - sunPresence)
        }
        .frame(width: R * 2, height: R * 2)
        .position(x: size.width / 2, y: centerY)
    }

    private func sunBody(radius R: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.96, blue: 0.75),
                             Color(red: 1.0, green: 0.80, blue: 0.38),
                             Color(red: 1.0, green: 0.60, blue: 0.26)],
                    center: .center, startRadius: 0, endRadius: R
                )
            )
            .frame(width: R * 2, height: R * 2)
            .shadow(color: Color(red: 1.0, green: 0.78, blue: 0.42).opacity(0.55), radius: 60)
    }

    private func moonBody(radius R: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(red: 0.97, green: 0.98, blue: 1.0),
                             Color(red: 0.87, green: 0.90, blue: 0.99),
                             Color(red: 0.77, green: 0.81, blue: 0.94)],
                    center: UnitPoint(x: 0.42, y: 0.4), startRadius: 0, endRadius: R
                )
            )
            .frame(width: R * 2, height: R * 2)
            .overlay {
                // A few soft craters near the visible top, for character.
                ZStack {
                    crater(dx: -0.10, dy: -0.34, scale: 0.075, in: R)
                    crater(dx: 0.12, dy: -0.30, scale: 0.05, in: R)
                    crater(dx: 0.02, dy: -0.24, scale: 0.11, in: R)
                }
            }
            .shadow(color: Color(red: 0.78, green: 0.83, blue: 1.0).opacity(0.5), radius: 48)
    }

    private func crater(dx: CGFloat, dy: CGFloat, scale: CGFloat, in R: CGFloat) -> some View {
        Circle()
            .fill(Color(red: 0.70, green: 0.74, blue: 0.89).opacity(0.55))
            .frame(width: R * 2 * scale, height: R * 2 * scale)
            .offset(x: R * 2 * dx, y: R * 2 * dy)
    }
}

/// A drag-driven wheel that reports its position *continuously* — including
/// fractional, between-item values — while the finger moves, then springs to the
/// nearest item and commits on release. Unlike SwiftUI's `.wheel` Picker (which
/// only writes its binding on settle), this lets the sky track the scroll live.
private struct TimeWheel<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    var foreground: Color = .black
    /// Contrasting color painted as a soft halo behind each digit, so numbers stay
    /// legible over any sky (including mid-tone dusk/dawn).
    var halo: Color = .clear
    let label: (Value) -> String
    var onScrub: (Double) -> Void = { _ in }

    private let rowHeight: CGFloat = 64

    @State private var committed = 0
    @State private var drag: CGFloat = 0
    @State private var lastTick = 0

    private var count: Int { values.count }

    /// Unclamped fractional index for the current drag (dragging down = earlier).
    private func fractional(_ d: CGFloat) -> Double {
        Double(committed) - Double(d / rowHeight)
    }

    private func clampedFractional(_ d: CGFloat) -> Double {
        min(max(fractional(d), 0), Double(count - 1))
    }

    var body: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let midY = geo.size.height / 2
            let frac = clampedFractional(drag)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(foreground.opacity(0.04))
                    .frame(height: rowHeight)
                    .position(x: midX, y: midY)

                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                    let dist: Double = Double(idx) - frac
                    let ad: Double = abs(dist)
                    let opacity: Double = max(0.12, 1 - ad * 0.34)
                    let scale: CGFloat = CGFloat(max(0.72, 1 - ad * 0.12))
                    let y: CGFloat = midY + CGFloat(dist) * rowHeight
                    if ad <= 3 {
                        Text(label(value))
                            .font(.system(size: 49, weight: .semibold, design: .serif))
                            .foregroundStyle(foreground.opacity(opacity))
                            .shadow(color: halo.opacity(opacity * 0.6), radius: 4)
                            .scaleEffect(scale)
                            .position(x: midX, y: y)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0),
                            .init(color: .black, location: 0.28),
                            .init(color: .black, location: 0.72),
                            .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // AFTER the mask: a mask also clips hit-testing, so define the draggable
            // area as the full frame here or the faded top/bottom become dead zones.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        drag = v.translation.height
                        let f = clampedFractional(drag)
                        let nearest = Int(f.rounded())
                        if nearest != lastTick {
                            lastTick = nearest
                            Haptics.tick(intensity: 0.5)
                        }
                        onScrub(f)
                    }
                    .onEnded { v in
                        // Carry a little momentum from the flick into the target.
                        let projected = v.translation.height
                            + (v.predictedEndTranslation.height - v.translation.height) * 0.5
                        let target = min(max(Int(fractional(projected).rounded()), 0), count - 1)
                        // Animate the drag to where `target` sits, keeping `committed`
                        // put so nothing jumps; normalize once the spring lands.
                        let targetDrag = CGFloat(committed - target) * rowHeight
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            drag = targetDrag
                        } completion: {
                            committed = target
                            drag = 0
                        }
                        lastTick = target
                        selection = values[target]
                        onScrub(Double(target))
                    }
            )
            .onAppear {
                if let i = values.firstIndex(of: selection) {
                    committed = i; lastTick = i
                }
            }
            .onChange(of: selection) { _, newVal in
                guard drag == 0, let i = values.firstIndex(of: newVal), i != committed else { return }
                committed = i; lastTick = i
            }
        }
    }
}

private struct DeliveryTimePicker: View {
    let wormName: String
    @Binding var hour12: Int
    @Binding var minute: Int
    @Binding var isPM: Bool
    /// Continuous hour24 (0..24), fired on every scrub so the backdrop can follow.
    var onLiveTime: (Double) -> Void

    private let hourValues = Array(1...12)
    private let minuteValues = Array(stride(from: 0, through: 55, by: 5))

    // Live fractional selections, updated while a wheel scrolls (not just on snap),
    // so the sky and the adaptive UI ink track the motion in real time.
    @State private var liveHour12: Double = 8
    @State private var liveMinute: Double = 0

    private func timeValue(hour12 h: Double, minute m: Double, pm: Bool) -> Double {
        h.truncatingRemainder(dividingBy: 12) + (pm ? 12 : 0) + m / 60
    }

    private var liveTime: Double { timeValue(hour12: liveHour12, minute: liveMinute, pm: isPM) }
    private var foreground: Color { DeliveryTimeBackdrop.foreground(at: liveTime) }
    private var onForeground: Color { DeliveryTimeBackdrop.onForeground(at: liveTime) }

    var body: some View {
        VStack(spacing: 22) {
            // One short line — no subtitle. The worm visits once a day; when.
            Text("when should \(wormName) bring your songs?")
                .font(.system(size: 27, weight: .bold, design: .serif))
                .foregroundStyle(foreground)
                .shadow(color: onForeground.opacity(0.45), radius: 5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 0) {
                TimeWheel(values: hourValues, selection: $hour12, foreground: foreground,
                          halo: onForeground, label: { "\($0)" }) { frac in
                    liveHour12 = frac + 1
                    onLiveTime(timeValue(hour12: frac + 1, minute: liveMinute, pm: isPM))
                }
                .frame(width: 150, height: 300)

                Text(":")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(foreground.opacity(0.5))
                    .shadow(color: onForeground.opacity(0.4), radius: 4)
                    .offset(y: -2)

                TimeWheel(values: minuteValues, selection: $minute, foreground: foreground,
                          halo: onForeground, label: { String(format: "%02d", $0) }) { frac in
                    liveMinute = frac * 5
                    onLiveTime(timeValue(hour12: liveHour12, minute: frac * 5, pm: isPM))
                }
                .frame(width: 150, height: 300)
            }

            amPmToggle
        }
        .padding(.top, 210)
        .animation(.easeInOut(duration: 0.3), value: liveTime)
        .onAppear {
            liveHour12 = Double(hour12)
            liveMinute = Double(minute)
            onLiveTime(liveTime)
        }
    }

    /// A clean two-up am/pm pill: the selected side is a filled capsule that
    /// slides across, instead of a cramped third wheel.
    private var amPmToggle: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { pm in
                Text(pm ? "pm" : "am")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPM == pm ? onForeground : foreground.opacity(0.5))
                    // Halo only on the unselected side; the selected sits on a filled pill.
                    .shadow(color: (isPM == pm ? Color.clear : onForeground).opacity(0.4), radius: 3)
                    .frame(width: 66, height: 42)
                    .contentShape(Capsule())
                    .onTapGesture {
                        guard isPM != pm else { return }
                        Haptics.impact(.light)
                        isPM = pm
                        onLiveTime(timeValue(hour12: liveHour12, minute: liveMinute, pm: pm))
                    }
            }
        }
        .background(alignment: isPM ? .trailing : .leading) {
            Capsule().fill(foreground).frame(width: 66, height: 42)
        }
        .padding(4)
        .background(Capsule().fill(foreground.opacity(0.12)))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isPM)
    }
}

/// A small numbered step marker beside a base apple: white disc, dotted ink
/// border, the step number. The caller dims it (via opacity) when the step
/// isn't live yet.
private struct BaseStepBadge: View {
    let number: Int
    let ink: Color

    var body: some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: 26, height: 26)
            .background(Circle().fill(.white))
            .overlay(
                Circle().strokeBorder(ink, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
            )
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}

/// The little label under a base apple: plain serif ink, no placard. Cohesive
/// with the serif header, nothing decorative.
private struct BaseAppleTag: View {
    let title: String
    let ink: Color
    let paper: Color

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .medium, design: .serif))
            .foregroundStyle(ink.opacity(0.6))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 120)
    }
}

/// When a step becomes active (the one before it was just eaten), give it a
/// springy scale pop so the unlock reads clearly.
private struct RevealPop: ViewModifier {
    let isActive: Bool
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isActive) { _, now in
                guard now else { return }
                scale = 1.45
                withAnimation(.spring(response: 0.7, dampingFraction: 0.5)) { scale = 1 }
            }
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

// MARK: - Delivery-time picker preview

/// Isolated, configurable preview of the delivery-time step: the picker over the
/// paper backdrop with the real "that's it" button below, so it can be tuned on
/// its own without booting the whole home entrance.
#Preview("Delivery time") {
    DeliveryTimePickerPreviewHost()
}

private struct DeliveryTimePickerPreviewHost: View {
    @State private var hour12 = 8
    @State private var minute = 0
    @State private var isPM = true
    @State private var liveTime: Double = 20

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let settledSize = OnboardingWormSize(length: 150, thickness: 24)
            ZStack {
                DeliveryTimeBackdrop(time: liveTime)
                    .zIndex(0)

                // The worm, settled on his bed, sharp in front of the sky.
                HomeWorm(
                    entranceStart: -100_000,
                    gulpStart: nil,
                    restCenter: CGPoint(x: W / 2, y: H * 0.78),
                    fromSize: settledSize,
                    toSize: settledSize,
                    entranceDuration: 2.9,
                    settleDuration: 0.7,
                    color: .black,
                    eyeColor: Color(red: 0.97, green: 0.96, blue: 0.93),
                    wiggles: [],
                    onTap: { _ in }
                )
                .zIndex(1)

                DeliveryTimePicker(
                    wormName: "wilbur",
                    hour12: $hour12,
                    minute: $minute,
                    isPM: $isPM,
                    onLiveTime: { liveTime = $0 }
                )
                .frame(maxWidth: 340)
                .position(x: W / 2, y: H * 0.24)
                .zIndex(2)

                Button {
                } label: {
                    Text("that's it")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(DeliveryTimeBackdrop.onForeground(at: liveTime))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DeliveryTimeBackdrop.foreground(at: liveTime), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 14)
                .animation(.easeInOut(duration: 0.3), value: liveTime)
                .zIndex(3)
            }
        }
        .ignoresSafeArea()
    }
}
