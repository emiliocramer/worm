import SwiftUI
import UIKit

// The lo-fi "digging" terminal that fills the waiting screen from the bottom up:
// timestamped log lines of what the worm is browsing, plus the odd framed page
// screenshot popping in like an iframe it cracked open. See
// docs/digging-log-spec.md. The timeline is a deterministic function of real
// wall-clock time since the dig began, so reopening after hours looks like it's
// genuinely been digging the whole time — not a loop.

// MARK: - Model

enum DigLane {
    case library, forums, reference, video, records, output, fault
}

struct DigStep {
    let offset: Double        // seconds from the burst start
    let lane: DigLane
    let verb: String          // uppercase, colored by family
    let desc: String          // uppercase description (may contain `artifact`)
    let artifact: String?     // bold + underlined payload word inside `desc`
    let shot: String?         // screenshot key (see DiggingLog.sites), or nil
}

struct DigJourney {
    let steps: [DigStep]
}

/// A scheduled log line at an absolute time.
struct DigEntry: Identifiable {
    let id: Int
    let date: Date
    let step: DigStep
}

/// The bounds of the underlined description text on the row currently being
/// viewed — so the beam can point at (and follow) that exact text.
private struct ViewedTextAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Content + palette

enum DiggingLog {
    static let ink   = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)

    /// Screenshot metadata → a fake browser chrome url + a page title. If a bundled
    /// image asset named the same as the key exists, the iframe shows it instead of
    /// the mock page.
    // Real pages, one per screenshot key. Drop a capture into Assets.xcassets named
    // exactly the key and the iframe shows it; otherwise a mock page uses url+title.
    // See docs/digging-journeys/digging-mockup-stories.md.
    static let sites: [String: (url: String, title: String)] = [
        "discogs-arcs":          ("discogs.com/master/878441", "The Arcs — Yours, Dreamily,"),
        "genius-maskoff":        ("genius.com/Future-mask-off-lyrics", "Mask Off — credits"),
        "wiki-nahwc":            ("en.wikipedia.org/wiki/Not_All_Heroes_Wear_Capes", "Not All Heroes Wear Capes"),
        "wiki-armagideon":       ("en.wikipedia.org/wiki/Armagideon_Time", "Armagideon Time"),
        "discogs-realrock":      ("discogs.com/search?q=sound+dimension+real+rock", "Sound Dimension — Real Rock"),
        "whosampled-realrock":   ("whosampled.com/sample/17272", "Armagideon Time ← Real Rock"),
        "discogs-aphex":         ("discogs.com/artist/45-Aphex-Twin", "Aphex Twin — aliases"),
        "archive-user18081971":  ("archive.org/details/aphex_twin_user18081971", "user18081971 · 230 tracks"),
        "wiki-humbleandkind":    ("en.wikipedia.org/wiki/Humble_and_Kind", "Humble and Kind"),
        "wiki-birdrifle":        ("en.wikipedia.org/wiki/The_Bird_%26_the_Rifle", "The Bird & the Rifle"),
        "whosampled-hungup":     ("whosampled.com/sample/2521", "Hung Up ← Gimme! Gimme! Gimme!"),
        "wiki-rebajada":         ("en.wikipedia.org/wiki/Rebajada", "Rebajada"),
        "yt-duenez":             ("youtube.com/watch?v=NWj8HQAgo6g", "Sonido Dueñez — rebajada mix"),
        "bandcamp-convulse":     ("convulserecords.bandcamp.com", "Convulse Records"),
        "bandcamp-shocktherapy": ("convulserecords.bandcamp.com/album/shock-therapy", "Gel / Cold Brats — Shock Therapy"),
        "wiki-otiswhisky":       ("en.wikipedia.org/wiki/In_Person_at_the_Whisky_a_Go_Go", "In Person at the Whisky a Go Go"),
        "discogs-otiswhisky":    ("discogs.com/search?q=otis+redding+whisky", "Otis Redding — Whisky (1968)"),
        "rym-sault":             ("rateyourmusic.com/artist/sault", "SAULT"),
        "pitchfork-sault":       ("pitchfork.com/news/sault-release-surprise-album-acts-of-faith-as-free-download", "SAULT release 5 new albums"),
        "wiki-goldberg1981":     ("en.wikipedia.org/wiki/Bach:_The_Goldberg_Variations_(1981_album)", "The Goldberg Variations (1981)"),
        "discogs-bargain":       ("discogs.com/sell/list", "Funk / Soul · price ascending"),
        "bandcamp-numeroprix":   ("numerogroup.com/products/eccentric-soul-the-prix-label", "Eccentric Soul: The Prix Label"),
        "credits-elcamino":      ("allmusic.com/album/el-camino-mw0002243314/credits", "El Camino — credits"),
        "wiki-realrock":         ("en.wikipedia.org/wiki/Real_Rock", "Real Rock — Sound Dimension"),
        "bandcamp-demos":        ("bandcamp.com/tag/hardcore?tab=all_releases", "Hardcore demos — name your price"),
        "discogs-goldberg1981":  ("discogs.com/search?q=glenn+gould+goldberg+variations+1981", "Glenn Gould — The Goldberg Variations (1981)"),
    ]

    private static func st(_ o: Double, _ l: DigLane, _ v: String, _ d: String,
                           _ a: String? = nil, _ s: String? = nil) -> DigStep {
        DigStep(offset: o, lane: l, verb: v, desc: d, artifact: a, shot: s)
    }

    // MARK: The canonical dig stories. Each follows a hero-journey pattern using
    // real records/credits/pages, so the log + screenshots read as a genuine dig.
    // See docs/digging-journeys/digging-mockup-stories.md.
    static let journeys: [DigJourney] = [
        // S01 — The Producer's Other Door (Black Keys → Danger Mouse → The Arcs).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "EL CAMINO: 41 PLAYS LOGGED"),
            st(5,   .reference, "READING",      "EL CAMINO CREDIT SHEET", "CREDIT", "credits-elcamino"),
            st(19,  .reference, "FINDING",      "PRODUCER: DANGER MOUSE"),
            st(42,  .reference, "TRACING",      "AUERBACH SIDE PROJECTS"),
            st(74,  .records,   "BROWSING",     "THE ARCS, DISCOGS", nil, "discogs-arcs"),
            st(262, .video,     "LISTENING",    "OUTTA MY MIND (2015)"),
            st(430, .output,    "SAVING",       "YOURS, DREAMILY, FULL LP"),
            st(447, .output,    "SYNTHESIZING", "VERDICT: SAME VOICE, NEW DOOR", "VERDICT"),
        ]),
        // S02 — If Young Metro Don't Trust You (Future → Metro Boomin).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "MASK OFF x30 THIS MONTH"),
            st(6,   .reference, "READING",      "GENIUS CREDITS: MASK OFF", "CREDIT", "genius-maskoff"),
            st(24,  .reference, "TRACING",      "METRO BOOMIN SOLO RUN"),
            st(51,  .records,   "BROWSING",     "NOT ALL HEROES WEAR CAPES", nil, "wiki-nahwc"),
            st(205, .video,     "LISTENING",    "10 FREAKY GIRLS, 21 SAVAGE"),
            st(344, .video,     "LISTENING",    "SUPERHERO FT. FUTURE"),
            st(401, .output,    "EXTRACTING",   "PRODUCER CHAIN, 3 NODES"),
            st(415, .output,    "RANKING",      "CREDIT LINE > TRACKLIST", "CREDIT"),
        ]),
        // S03 — 387 Versions Deep (Clash → Willie Williams → Real Rock riddim).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "CLASH B-SIDES ON REPEAT"),
            st(7,   .reference, "READING",      "ARMAGIDEON TIME, ORIGINS", nil, "wiki-armagideon"),
            st(26,  .reference, "TRACING",      "RIDDIM: REAL ROCK, 1967", "RIDDIM", "wiki-realrock"),
            st(63,  .records,   "BROWSING",     "SOUND DIMENSION 7-INCH", nil, "discogs-realrock"),
            st(231, .video,     "LISTENING",    "WILLIE WILLIAMS, 1979 CUT"),
            st(305, .records,   "COMPARING",    "387 VERSIONS ON RECORD", "VERSION", "whosampled-realrock"),
            st(349, .output,    "SAVING",       "REAL ROCK FAMILY TREE"),
            st(361, .output,    "RANKING",      "ONE RIDDIM, PICK THREE", "RIDDIM"),
        ]),
        // S04 — The Man With 20 Names (Aphex Twin aliases). Holds the one joke.
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "SAW 85-92, EVERY NIGHT"),
            st(8,   .reference, "READING",      "RDJ ALIAS LIST, 20+ NAMES", "ALIAS", "discogs-aphex"),
            st(33,  .records,   "BROWSING",     "POLYGON WINDOW, WARP 1993"),
            st(158, .video,     "LISTENING",    "QUOTH, SINE WAVES LP"),
            st(262, .forums,    "READING",      "RDJ INTERVIEW, MOSTLY LIES"),
            st(291, .records,   "BROWSING",     "THE TUSS: RUSHUP EDGE"),
            st(337, .records,   "CRAWLING",     "USER18081971, 230 TRACKS", nil, "archive-user18081971"),
            st(420, .output,    "SAVING",       "ALIAS TREE COMPLETE", "ALIAS"),
            st(438, .output,    "SYNTHESIZING", "SAME HANDS, NEW NAMES"),
        ]),
        // S05 — Who Wrote That (Tim McGraw → Lori McKenna).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "HUMBLE AND KIND, 14 PLAYS"),
            st(5,   .reference, "READING",      "SOLE WRITER: LORI McKENNA", nil, "wiki-humbleandkind"),
            st(23,  .reference, "TRACING",      "ALSO WROTE: GIRL CRUSH"),
            st(58,  .records,   "BROWSING",     "THE BIRD & THE RIFLE, 2016", nil, "wiki-birdrifle"),
            st(214, .video,     "LISTENING",    "WRECK YOU, TRACK ONE"),
            st(388, .video,     "LISTENING",    "HER OWN HUMBLE AND KIND"),
            st(421, .output,    "EXTRACTING",   "THE WRITER'S OWN VERSION", "VERSION"),
            st(436, .output,    "SYNTHESIZING", "SHADOW STEPS FORWARD"),
        ]),
        // S06 — Where the Riff Came From (Madonna → ABBA).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "HUNG UP, TOP TRACK 2 YRS"),
            st(4,   .records,   "TRACING",      "WHOSAMPLED: HUNG UP", nil, "whosampled-hungup"),
            st(21,  .reference, "READING",      "GIMME! GIMME! GIMME! 1979"),
            st(47,  .video,     "LISTENING",    "ABBA SYNTH LINE AT 0:12"),
            st(176, .records,   "CRAWLING",     "WHO ELSE PULLED THIS RIFF"),
            st(243, .output,    "SAVING",       "SOURCE DNA, ONE SAMPLE", "SAMPLE"),
            st(259, .output,    "RANKING",      "THE ORIGINAL STILL WINS"),
        ]),
        // S07 — Slower Hits Harder (cumbia rebajada, Monterrey).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "CUMBIA CREEPING INTO MIX"),
            st(9,   .reference, "READING",      "REBAJADA: THE SLOW GENRE", "GENRE", "wiki-rebajada"),
            st(44,  .reference, "TRACING",      "COLOMBIA TO MONTERREY"),
            st(96,  .forums,    "FINDING",      "SONIDO DUEÑEZ, NAMED TWICE"),
            st(138, .video,     "WATCHING",     "DUEÑEZ CASSETTE MIX", nil, "yt-duenez"),
            st(402, .output,    "EXTRACTING",   "45s DRAGGED DOWN TO 33"),
            st(425, .output,    "SAVING",       "REBAJADA GENRE NODE", "GENRE"),
            st(441, .output,    "SYNTHESIZING", "SLOWER HITS HARDER"),
        ]),
        // S08 — Seven Inches of Therapy (Convulse split & demo).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "HARDCORE SPIKE, 2AM PLAYS"),
            st(6,   .records,   "BROWSING",     "CONVULSE RECORDS BANDCAMP", nil, "bandcamp-convulse"),
            st(38,  .records,   "FINDING",      "GEL / COLD BRATS SPLIT", nil, "bandcamp-shocktherapy"),
            st(121, .video,     "LISTENING",    "SHOCK THERAPY, GEL SIDE"),
            st(254, .records,   "CRAWLING",     "DEMO TAPES, NAME-YR-PRICE", "DEMO", "bandcamp-demos"),
            st(291, .forums,    "READING",      "R/HARDCORE DEMO ROUNDUP"),
            st(333, .output,    "SAVING",       "SPLIT + DEMO SHORTLIST", "DEMO"),
            st(351, .output,    "RANKING",      "DIY BEATS POLISH"),
        ]),
        // S09 — The Whisky, April '66 (Otis Redding live).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "OTIS: STUDIO CUTS ONLY"),
            st(8,   .reference, "READING",      "WHISKY A GO GO, APR 1966", nil, "wiki-otiswhisky"),
            st(32,  .records,   "BROWSING",     "1968 ATCO PRESSING", "PRESSING", "discogs-otiswhisky"),
            st(187, .video,     "LISTENING",    "MR. PITIFUL, LIVE TAKE"),
            st(414, .video,     "LISTENING",    "CROWD LOUD ON RESPECT"),
            st(452, .output,    "EXTRACTING",   "LIVE VERSION > STUDIO", "VERSION"),
            st(468, .output,    "SYNTHESIZING", "THE ROOM IS THE POINT"),
        ]),
        // S10 — Password: godislove (SAULT anonymous drop).
        DigJourney(steps: [
            st(0,   .forums,    "FINDING",      "SAULT DROP THREAD, RYM", nil, "rym-sault"),
            st(16,  .reference, "READING",      "5 ALBUMS, 5 DAYS, LOCKED", nil, "pitchfork-sault"),
            st(42,  .reference, "FINDING",      "PASSWORD WAS GODISLOVE"),
            st(71,  .records,   "BROWSING",     "FOREVER LIVING ORIGINALS"),
            st(204, .video,     "LISTENING",    "UNTITLED (GOD), DISC 5"),
            st(396, .output,    "SAVING",       "NO-NAME DISCOGRAPHY MAP"),
            st(417, .output,    "SYNTHESIZING", "VERDICT: FACELESS, FLAWLESS", "VERDICT"),
        ]),
        // S11 — Two Lives, One Score (Gould's two Goldbergs).
        DigJourney(steps: [
            st(0,   .library,   "PROCESS",      "GOLDBERGS: WHICH GOULD?"),
            st(11,  .reference, "READING",      "1955 VS 1981, THE DEBATE", nil, "wiki-goldberg1981"),
            st(46,  .video,     "LISTENING",    "ARIA, 1955: RUNS 1:53"),
            st(173, .video,     "LISTENING",    "ARIA, 1981: RUNS 3:05"),
            st(301, .forums,    "COMPARING",    "R/CLASSICALMUSIC TAKES"),
            st(342, .records,   "BROWSING",     "1981 EARLY DIGITAL PRESSING", "PRESSING", "discogs-goldberg1981"),
            st(384, .output,    "EXTRACTING",   "TWO LIVES, ONE SCORE"),
            st(405, .output,    "RANKING",      "1981 VERSION FOR TONIGHT", "VERSION"),
        ]),
        // S12 — The Dollar Reel (Prix Records / Penny & the Quarters).
        DigJourney(steps: [
            st(0,   .forums,    "FINDING",      "DOLLAR-BIN THREAD, R/VINYL"),
            st(27,  .records,   "CRAWLING",     "DISCOGS UNDER $5, SOUL", nil, "discogs-bargain"),
            st(94,  .records,   "FINDING",      "PRIX RECORDS, COLUMBUS OH"),
            st(133, .reference, "READING",      "PENNY & THE QUARTERS STORY"),
            st(297, .video,     "LISTENING",    "YOU AND ME, ONE TAKE"),
            st(341, .records,   "BROWSING",     "ECCENTRIC SOUL: PRIX", nil, "bandcamp-numeroprix"),
            st(383, .output,    "SAVING",       "A $1 REEL, PRICELESS DEMO", "DEMO"),
            st(401, .output,    "RANKING",      "CHEAP RISK PAID OFF"),
        ]),
    ]

    /// The closing climax burst — same every dig, lands ~2 min before delivery and
    /// resolves the search into the result the notification promises.
    static let closingJourney = DigJourney(steps: [
        st(0,   .output, "SYNTHESIZING", "FOLDING TRAILS INTO TASTE", "TASTE"),
        st(34,  .output, "RANKING",      "40 CANDIDATES DOWN TO 9"),
        st(79,  .output, "SKIPPING",     "6 TOO CLOSE TO KNOWN PLAYS"),
        st(112, .output, "SAVING",       "PICKED 3 SONGS. VERDICT IN", "VERDICT"),
    ])
}

// MARK: - Seeded RNG (stable per dig-start, avalanched for nearby timestamps)

struct DigRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        // Raw Date seeds differ by tiny amounts. Feeding those straight into an
        // xorshift leaves the high bits nearly empty, which made Int.random's
        // first 0..<12 draw resolve to journey zero over and over. SplitMix's
        // avalanche gives adjacent dig starts unrelated first draws.
        var mixed = seed &+ 0x9E3779B97F4A7C15
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        state = mixed ^ (mixed >> 31)
        if state == 0 { state = 0x9E3779B97F4A7C15 }
    }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - View

struct DiggingLogView: View {
    let deliveryHour: Int
    let deliveryMinute: Int
    /// Preview-only: compress the t
    /// imeline ~20× and stream continuously, so the
    /// whole system (rows, colors, cursor, iframes, connectors) is visible fast.
    var previewFast: Bool = false

    @AppStorage(NodeProgression.deliveryTestDeadlineKey) private var deliveryTestDeadlineRaw: Double = 0

    @State private var entries: [DigEntry] = []
    /// A page the user explicitly opened from an underlined source line.
    @State private var pinned: DigEntry?
    /// The terminal follows output until the person starts reading earlier work.
    @State private var followsLatest = true
    /// The row pinned to the bottom while live-following. A bound scroll target
    /// updates in the same layout transaction as an append, avoiding a second,
    /// asynchronous jump one frame later.
    @State private var scrollTarget: Int?
    /// This visual trace belongs to the current Home session. It deliberately
    /// starts empty every time Home mounts; persisted dig state is not replayed.
    @State private var sessionStartedAt: Date?

    private let livePromptHeight: CGFloat = 34
    private let bottomPad: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                content(now: ctx.date, size: geo.size)
            }
        }
        .background(DiggingLog.paper.ignoresSafeArea())
        .onAppear {
            let start = Date()
            sessionStartedAt = start
            rebuild(startingAt: start)
            followsLatest = true
        }
        .onChange(of: deliveryTestDeadlineRaw) { _, _ in
            rebuild(startingAt: sessionStartedAt ?? Date())
        }
    }

    private func content(now: Date, size: CGSize) -> some View {
        let shown = entries.filter { $0.date <= now }
        let terminalEntries = shown
        let blink = Int(now.timeIntervalSinceReferenceDate) % 2 == 0
        let displayShot = pinned

        // Card geometry — shared by the frame and the beam overlay.
        let cardW = min(240, size.width - 120)          // narrower: clear paper on both sides
        let cardH = min(cardW * 1.3, size.height * 0.44)
        let cardTop = max(300, size.height * 0.36)      // dropped lower, well clear of the copy
        let center = CGPoint(x: size.width * 0.5, y: cardTop + cardH / 2)
        let bl = CGPoint(x: center.x - cardW / 2 + 14, y: center.y + cardH / 2)
        let br = CGPoint(x: center.x + cardW / 2 - 14, y: center.y + cardH / 2)
        let tl = CGPoint(x: center.x - cardW / 2 + 14, y: center.y - cardH / 2)
        let tr = CGPoint(x: center.x + cardW / 2 - 14, y: center.y - cardH / 2)

        return ZStack {
            // Scrollable terminal history. The live activity line is deliberately
            // outside this scroller, fixed to Home's bottom edge.
            // Tap empty space (below the rows) to close an open frame. Sits UNDER
            // the rows so tapping a link hits the row first (which replaces/opens).
            if displayShot != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeFrame() }
                    .zIndex(0)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(terminalEntries) { entry in
                        DigLogRow(
                            step: entry.step,
                            viewing: entry.id == displayShot?.id,
                            onSourceTap: entry.step.shot == nil ? nil : { pin(entry) }
                        )
                        .frame(height: DigLogRow.height(for: entry.step), alignment: .leading)
                        .id(entry.id)
                    }
                }
                .scrollTargetLayout()
                .frame(
                    minHeight: max(0, size.height - livePromptHeight - bottomPad),
                    alignment: .bottomLeading
                )
                .padding(.leading, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition(id: $scrollTarget, anchor: .bottom)
            .padding(.bottom, livePromptHeight + bottomPad)
            .onChange(of: terminalEntries.last?.id, initial: true) { _, newest in
                guard followsLatest, let newest else { return }
                withAnimation(.easeOut(duration: 0.20)) {
                    scrollTarget = newest
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4).onChanged { _ in
                    if followsLatest {
                        followsLatest = false
                    }
                }
            )
            // A normal tap on the research surface dismisses the page. Buttons
            // above this gesture still open/replace pages, and a drag continues
            // to belong to the ScrollView.
            .onTapGesture {
                guard displayShot != nil else { return }
                closeFrame()
            }
            .zIndex(1)

            DigLivePrompt(step: terminalEntries.last?.step, blink: blink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: livePromptHeight, alignment: .leading)
                .background(DiggingLog.paper)
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 10)
                .padding(.bottom, bottomPad)
                .zIndex(2)

            // The framed page — smooth SwiftUI transition in/out, per-frame page scan.
            if let shot = displayShot, let key = shot.step.shot {
                ZStack(alignment: .topTrailing) {
                    DigIframe(key: key, since: shot.date)

                    Button { closeFrame() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.72))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.94), in: Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 10, y: -10)
                    .accessibilityLabel("Close page")
                }
                .frame(width: cardW, height: cardH)
                .position(center)
                .id(shot.id)
                .zIndex(3)
            }
        }
        // Beam that points at — and follows — the underlined description text of the
        // row being viewed, tracking it as the log scrolls up.
        .overlayPreferenceValue(ViewedTextAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let rect = proxy[anchor]
                    let apex = CGPoint(x: rect.minX + 3, y: rect.midY)
                    // When the line sits beside/behind the frame, the beam would cross
                    // it — just hide it in that case.
                    let behindFrame = apex.y > cardTop && apex.y < cardTop + cardH
                    if !behindFrame {
                        // Come out of the card edge nearest the line: bottom (point down)
                        // when the line is below the frame, top (point up) when above.
                        let fromTop = apex.y < center.y
                        let a = fromTop ? tl : bl
                        let b = fromTop ? tr : br
                        ZStack {
                            Path { p in
                                p.move(to: a); p.addLine(to: apex); p.addLine(to: b); p.closeSubpath()
                            }
                            .fill(DiggingLog.ink.opacity(0.05))
                            Path { p in
                                p.move(to: a); p.addLine(to: apex)
                                p.move(to: b); p.addLine(to: apex)
                            }
                            .stroke(DiggingLog.ink.opacity(0.7), lineWidth: 1)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.28), value: displayShot?.id)
        }
    }

    /// Close the page the person opened. Incoming logs never replace it.
    private func closeFrame() {
        Haptics.impact(.light)
        pinned = nil
    }

    private func pin(_ entry: DigEntry) {
        guard entry.step.shot != nil else { return }
        Haptics.impact(.light)
        pinned = DigEntry(id: entry.id, date: Date(), step: entry.step)
    }

    // MARK: - Timeline

    private func rebuild(startingAt sessionStart: Date) {
        if previewFast {
            entries = Self.previewSchedule()
            return
        }
        entries = Self.schedule(digStart: sessionStart, delivery: nextDelivery(from: sessionStart))
    }

    private func nextDelivery(from date: Date) -> Date {
        if deliveryTestDeadlineRaw > 0 {
            return Date(timeIntervalSinceReferenceDate: deliveryTestDeadlineRaw)
        }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = deliveryHour
        comps.minute = deliveryMinute
        comps.second = 0
        let today = Calendar.current.date(from: comps) ?? date
        return today > date ? today : (Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    /// Build a deterministic research trace from the authored source journeys.
    /// A route takes time: a page opens, the worm reads/listens, then follows the
    /// next lead. We do not fill the gaps with generic "activity" lines.
    static func schedule(digStart: Date, delivery: Date) -> [DigEntry] {
        var out: [(Date, DigStep)] = []
        let milliseconds = Int64((digStart.timeIntervalSinceReferenceDate * 1_000).rounded())
        var rng = DigRNG(seed: UInt64(bitPattern: milliseconds))

        let close = DiggingLog.closingJourney
        let closeLen = close.steps.last?.offset ?? 0
        let closeStart = delivery.addingTimeInterval(-(closeLen + 6))

        // The source stories are authored in research-time seconds. Keep their
        // pauses legible instead of compressing a whole investigation into a few
        // seconds; a fresh source event should feel consequential.
        let activityScale = 0.16
        var t = digStart
        var lastJourney = -1
        var journeyDeck: [Int] = []
        var guardCount = 0
        while t < closeStart.addingTimeInterval(-20), guardCount < 400 {
            guardCount += 1
            if journeyDeck.isEmpty {
                journeyDeck = Array(DiggingLog.journeys.indices)
                journeyDeck.shuffle(using: &rng)
                if journeyDeck.count > 1, journeyDeck.first == lastJourney {
                    journeyDeck.swapAt(0, 1)
                }
            }
            let idx = journeyDeck.removeFirst()
            lastJourney = idx
            let j = DiggingLog.journeys[idx]
            append(journey: j, startingAt: t, scale: activityScale, into: &out)
            let dur = (j.steps.last?.offset ?? 0) * activityScale
            // A route closes before the next one starts. This is the natural
            // breathing room of research, not a fake idle state.
            let gap = Double.random(in: 6...18, using: &rng)
            t = t.addingTimeInterval(dur + gap)
        }

        // Closing climax, always, ending right at delivery.
        append(journey: close, startingAt: closeStart, scale: 1, into: &out)

        return out
            .filter { $0.0 <= delivery }
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { DigEntry(id: $0.offset, date: $0.element.0, step: $0.element.1) }
    }

    /// Every screenshot-backed route opens a source before the authored action
    /// reads it. This is deliberately specific to the page being shown, and gives
    /// the browser frame a proper cause-and-effect moment in the transcript.
    private static func append(
        journey: DigJourney,
        startingAt start: Date,
        scale: Double,
        into output: inout [(Date, DigStep)]
    ) {
        for (index, step) in journey.steps.enumerated() {
            let date = start.addingTimeInterval(step.offset * scale)
            let next = index < journey.steps.count - 1 ? journey.steps[index + 1] : nil
            if let shot = step.shot, let site = DiggingLog.sites[shot] {
                let host = site.url.split(separator: "/").first.map(String.init)?.uppercased() ?? "SOURCE"
                let opening = DigStep(
                    offset: 0,
                    lane: step.lane,
                    verb: "OPENING",
                    desc: "\(host) > \(site.title.uppercased())",
                    artifact: nil,
                    shot: nil
                )
                let openingLead = max(0.25, min(1.4, scale * 3))
                output.append((date.addingTimeInterval(-openingLead), opening))
            }
            output.append((date, expanded(step, next: next, ordinal: index)))

            // Long source reads have a visible, route-specific reasoning step:
            // the exact lead being tested against the next named source.
            guard let next else { continue }
            let authoredGap = next.offset - step.offset
            guard authoredGap >= 55 else { continue }
            let gap = authoredGap * scale
            let connection = DigStep(
                offset: 0,
                lane: .output,
                verb: "LINKING",
                desc: "\(step.desc) > \(next.desc) > TESTING CONNECTION",
                artifact: nil,
                shot: nil
            )
            output.append((date.addingTimeInterval(gap * 0.52), connection))
        }
    }

    /// Turn terse authored beats into a readable research trail. The continuation
    /// is journey-specific—the next real lead—not generic filler, so most lines
    /// explain both what just happened and where the worm is going next.
    private static func expanded(_ step: DigStep, next: DigStep?, ordinal: Int) -> DigStep {
        let continuation: String
        if let next {
            switch step.verb {
            case "PROCESS":
                continuation = "STARTING WITH \(next.desc)"
            case "READING":
                continuation = "PULLING A LEAD TOWARD \(next.desc)"
            case "TRACING":
                continuation = "NEXT STOP: \(next.desc)"
            case "BROWSING", "CRAWLING":
                continuation = "RELATED HIT: \(next.desc)"
            case "LISTENING", "WATCHING":
                continuation = "CHECKING AGAINST \(next.desc)"
            case "FINDING":
                continuation = "LEAD OPENS \(next.desc)"
            case "COMPARING":
                continuation = "MATCHING AGAINST \(next.desc)"
            case "SAVING", "EXTRACTING":
                continuation = "QUEUED BEFORE \(next.desc)"
            case "RANKING", "SYNTHESIZING", "SKIPPING":
                continuation = "NEXT PASS: \(next.desc)"
            default:
                let labels = ["NEXT", "FOLLOWING", "CROSS-CHECKING"]
                continuation = "\(labels[ordinal % labels.count]): \(next.desc)"
            }
        } else {
            let endings = [
                "ROUTE CLOSED; NOTE SAVED",
                "SOURCE TRAIL COMPLETE",
                "EVIDENCE ADDED TO THE DIG"
            ]
            continuation = endings[ordinal % endings.count]
        }

        return DigStep(
            offset: step.offset,
            lane: step.lane,
            verb: step.verb,
            desc: "\(step.desc) > \(continuation)",
            artifact: step.artifact,
            shot: step.shot
        )
    }

    /// A deliberately paced preview stream. It starts with an in-progress source
    /// route so the Home canvas opens on real evidence and a visible browser frame.
    static func previewSchedule() -> [DigEntry] {
        let now = Date()
        var out: [(Date, DigStep)] = []
        var rng = DigRNG(seed: 20_240_607)
        var t = now.addingTimeInterval(-16)
        let scale = 0.05
        let gap = 2.0
        var last = -1
        var journeyDeck: [Int] = []
        for _ in 0..<120 {
            if journeyDeck.isEmpty {
                journeyDeck = Array(DiggingLog.journeys.indices)
                journeyDeck.shuffle(using: &rng)
                if journeyDeck.count > 1, journeyDeck.first == last {
                    journeyDeck.swapAt(0, 1)
                }
            }
            let idx = journeyDeck.removeFirst()
            last = idx
            let j = DiggingLog.journeys[idx]
            append(journey: j, startingAt: t, scale: scale, into: &out)
            let burstLen = (j.steps.last?.offset ?? 0) * scale
            t = t.addingTimeInterval(burstLen + gap)
        }
        return out
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { DigEntry(id: $0.offset, date: $0.element.0, step: $0.element.1) }
    }

}

// MARK: - Log row

/// One compact research event. The lane dot, quiet clock, strong action, and
/// description create a readable hierarchy without turning each row into a card.
private struct DigLogRow: View {
    let step: DigStep
    /// True while its screenshot is open — the whole description underlines to read
    /// as "this is what's being viewed."
    var viewing: Bool = false
    /// Only screenshot-backed, underlined source text receives this action.
    var onSourceTap: (() -> Void)? = nil

    private var isRouteOrigin: Bool { step.verb == "PROCESS" }
    private var isSourceVisit: Bool { step.shot != nil }
    private var isReasoning: Bool { step.verb == "LINKING" }

    static func height(for step: DigStep) -> CGFloat {
        if step.verb == "PROCESS" { return 46 }
        if step.shot != nil { return 32 }
        return 25
    }

    @ViewBuilder
    var body: some View {
        if isSourceVisit {
            Button {
                onSourceTap?()
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        Group {
            if isRouteOrigin {
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.verb)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(DiggingLog.ink.opacity(0.42))
                    descriptionText
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .anchorPreference(key: ViewedTextAnchorKey.self, value: .bounds) {
                            viewing ? $0 : nil
                        }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 5)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(step.verb)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(DiggingLog.ink.opacity(0.42))
                        .frame(width: 76, alignment: .leading)
                    descriptionText
                        .font(.system(size: 13, weight: isSourceVisit ? .semibold : .regular, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .anchorPreference(key: ViewedTextAnchorKey.self, value: .bounds) {
                            viewing ? $0 : nil
                        }
                }
                .padding(.horizontal, 5)
                .padding(.leading, isReasoning ? 12 : 0)
                .opacity(isReasoning ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(viewing ? DiggingLog.ink.opacity(0.045) : .clear)
    }

    private var descriptionText: Text {
        // Underline == has a screenshot == tappable. Anything without a shot is
        // plain text (no dangling underline you can't click).
        let u = step.shot != nil
        guard let artifact = step.artifact, let range = step.desc.range(of: artifact) else {
            return Text(step.desc).foregroundColor(DiggingLog.ink).underline(u)
        }
        let pre = String(step.desc[step.desc.startIndex..<range.lowerBound])
        let post = String(step.desc[range.upperBound...])
        return Text(pre).foregroundColor(DiggingLog.ink).underline(u)
            + Text(artifact).foregroundColor(DiggingLog.ink).bold().underline(u)
            + Text(post).foregroundColor(DiggingLog.ink).underline(u)
    }
}

/// The terminal's bottom edge behaves like a model's live work indicator: it
/// keeps changing between substantive rows and makes the crawler feel occupied.
private struct DigLivePrompt: View {
    let step: DigStep?
    let blink: Bool

    private var current: (verb: String, detail: String) {
        guard let step else { return ("PROCESS", "OPENING TODAY'S DIG") }
        return (step.verb, step.desc)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(current.verb)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(DiggingLog.ink.opacity(0.58))
            Text(current.detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DiggingLog.ink.opacity(0.76))
                .lineLimit(1)
            Text("▍")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(DiggingLog.ink)
                .opacity(blink ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(DiggingLog.ink.opacity(0.12)).frame(height: 1)
        }
    }
}

// MARK: - The iframe

/// A framed "page the worm cracked open." If a bundled image asset named `key`
/// exists it shows that real capture; otherwise a lo-fi mock page (browser chrome
/// + title + skeleton content), so the mechanic reads even before real captures
/// are dropped in.
private struct DigIframe: View {
    let key: String
    /// When the screenshot opened. Drives a smooth, per-frame page scroll (the
    /// worm scanning/reading the site) independent of the outer 1s log tick.
    var since: Date? = nil

    var body: some View {
        TimelineView(.animation) { ctx in
            let elapsed = since.map { ctx.date.timeIntervalSince($0) } ?? 0
            let scan = min(1, max(0, (elapsed - 0.4) / 9))
            page(scan: scan)
        }
    }

    private func page(scan: Double) -> some View {
        let meta = DiggingLog.sites[key]
        // Start a touch high (page top), drift down as it "reads."
        let panOffset = 20 - scan * 44
        return VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.black.opacity(0.18)).frame(width: 6, height: 6)
                }
                Text(meta?.url ?? "")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.black.opacity(0.5))
                    .lineLimit(1)
                    .padding(.leading, 4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.9))

            Group {
                if let img = UIImage(named: key) {
                    Image(uiImage: img).resizable().scaledToFill().offset(y: panOffset)
                } else {
                    mockPage(title: meta?.title ?? "").offset(y: panOffset * 0.4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.black, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }

    private func mockPage(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(.black.opacity(0.82))
                .lineLimit(2)
            skeletonLine(0.9)
            skeletonLine(0.75)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.08))
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
            skeletonLine(0.85)
            skeletonLine(0.6)
            skeletonLine(0.8)
            skeletonLine(0.4)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private func skeletonLine(_ widthFraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.black.opacity(0.10))
            .frame(height: 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: widthFraction, anchor: .leading)
    }
}

// MARK: - Previews

/// The full waiting screen: the countdown header over the streaming digging log,
/// timeline compressed so it's alive in the canvas.
#Preview("Waiting screen") {
    ZStack(alignment: .top) {
        DiggingLogView(deliveryHour: 20, deliveryMinute: 0, previewFast: true)
        VStack(spacing: 4) {
            Text("i'll be back in")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundColor(DiggingLog.ink.opacity(0.8))
            Text("6h 34m")
                .font(.system(size: 46, weight: .heavy, design: .serif))
                .foregroundColor(DiggingLog.ink)
        }
        .padding(.top, 96)
    }
    .ignoresSafeArea()
}

/// Just the log, streaming fast — focus on rows, colors, cursor, iframes, connectors.
#Preview("Digging log — fast") {
    DiggingLogView(deliveryHour: 20, deliveryMinute: 0, previewFast: true)
}

/// Static tuner: one row per lane/verb (incl. artifact underline, cursor) plus an
/// iframe, so styling can be edited without waiting for animation.
#Preview("Components") {
    DigComponentsPreview()
}

private struct DigComponentsPreview: View {
    private let samples: [DigStep] = [
        DigStep(offset: 0, lane: .library,   verb: "CONNECTING",   desc: "SCANNING SPOTIFY LIBRARY", artifact: nil, shot: nil),
        DigStep(offset: 0, lane: .forums,    verb: "BROWSING",     desc: "r/VINYLHEADS TOP OF WEEK", artifact: nil, shot: nil),
        DigStep(offset: 0, lane: .reference, verb: "FINDING",      desc: "SYNTHESIZING PROFILE", artifact: "PROFILE", shot: nil),
        DigStep(offset: 0, lane: .records,   verb: "EXTRACTING",   desc: "SAVING FAVOURITE GENRE", artifact: "GENRE", shot: nil),
        DigStep(offset: 0, lane: .video,     verb: "WATCHING",     desc: "WATCHING REVIEW", artifact: "REVIEW", shot: nil),
        DigStep(offset: 0, lane: .output,    verb: "RANKING",      desc: "RANKING 340 CANDIDATES", artifact: nil, shot: nil),
        DigStep(offset: 0, lane: .fault,     verb: "RATE-LIMITED", desc: "BACKING OFF 40s", artifact: nil, shot: nil),
    ]

    var body: some View {
        ZStack {
            DiggingLog.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(samples.enumerated()), id: \.offset) { i, step in
                    DigLogRow(step: step)
                }
                DigIframe(key: "wiki_metro")
                    .frame(width: 260, height: 320)
                    .padding(.top, 16)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
