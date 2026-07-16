# Worm — the baseline

> This is the source of truth for what Worm *is* and the bar every feature is
> held to. Read it before building. If a change contradicts this doc, the doc
> wins — or the doc gets updated deliberately, not drifted past.

## 1. The thesis

**The worm is your taste profile.** Not a chatbot bolted onto your data, not a
dashboard, not a settings screen with a mascot. The worm *is* the thing — the
living representation of who you are, assembled from everything we can pull off
your devices and accounts.

The whole product rests on one feeling: **"this knows me — better than any
algorithm, better than a year-in-review, better than I could say it myself."**

We earn that feeling by being *specific and right* about something the user
didn't expect us to notice. One good sentence beats a hundred data points.

The first monetizable proof is music discovery, but Worm is **not a music
profile**. The north star is:

> **Taste -> music.**
>
> Given the whole taste profile, surface one real, niche song the user has never
> heard that feels inevitable once they hear it.

Music nodes are evidence. They are not the product boundary. Spotify should not
just lead to "Spotify-but-deeper"; Photos, Calendar, media habits, places,
objects, aesthetics, rituals, creators, and obsessions must all be able to pull
the recommendation away from what a normal music recommender would choose.

## 2. The mental model — three layers

```
NODES  ──►  TASTE PROFILE  ──►  WORM
(dense data)  (synthesis)        (voice / character / surface)
```

- **Nodes** — dense data sources behind a permission or an account: Spotify,
  Apple Music, YouTube, Contacts, Photos, Calendar, and (later)
  Health-if-ever-granted, Messages metadata, location, etc. A node's job is
  singular and absolute: **extract every drop of data the source will give us,
  and keep it.** See the node rules below.
- **Taste profile** — the synthesized understanding derived *across* nodes: what
  the user loves, avoids, is drifting toward, is nostalgic for, repeats, saves,
  visits, photographs, watches, reads, schedules, connects with, and quietly
  returns to. It is not a music profile. Music recommendation is one output of
  the whole profile.
- **Worm** — the character that surfaces the profile. The worm speaks. Insights
  come out of the worm's mouth, in the worm's voice. The worm gets visibly
  *smarter* as more nodes connect — that progression is a core feeling, not a
  side effect.

**More nodes + more permissions ⇒ a smarter worm.** That relationship is the
growth loop of the entire app.

### How the brain works (the synthesis architecture)

The taste profile is a standalone **brain entity**
(`Worm/Profile/TasteProfile.swift`) that surfaces *tap into* — it is not owned by
the FTUE, Spotify, or any single node.

Pipeline:

```
RAW NODES -> NODE BRAIN SLICES -> BRAIN CONTEXT -> RETRIEVAL -> CLAUDE -> WORM SURFACES
```

- **Node brain slices** (`NodeBrainSlice`) are cheap, deterministic, on-device
  reductions of each raw node. A slice is the node's small brain: summary,
  high-signal facts, evidence strings, retrieval-ready chunks, freshness,
  confidence, health, and local novelty memory. Raw snapshots stay local.
- **Brain context** (`BrainContext`) combines all available slices, the durable
  private `read`, surfaced insights, and novelty filters. During onboarding this
  may contain only Spotify; after profile setup it can contain Spotify, Apple
  Music, YouTube, Contacts, Photos, and Calendar together.
- **Brain retrieval** (`BrainRetriever`) ranks compact slice memories locally for
  each direct question. V1 is deterministic lexical retrieval with node intent,
  confidence, and freshness weighting. No embeddings or vector store until real
  usage proves the added complexity improves answer quality.
- **Brain synthesizer** (`BrainSynthesizer` -> `ClaudeClient`) is the only
  model-facing boundary. `ClaudeClient` is transport-only; it knows nothing
  about Spotify or any node. Structured outputs return reads, insights, and
  direct answers from retrieved working context, each with evidence and
  confidence.
- **Local novelty checks** run after music recommendations. If Claude suggests
  a known track, artist, or album from Spotify/Apple Music memory, the brain
  rejects it and asks again before surfacing anything.
- **Catalog verification** is mandatory for music discovery. No exact Spotify or
  Apple Music catalog match, no recommendation. The brain must fail honestly
  rather than invent a plausible song.

Rules find facts; the model finds *meaning*. We tried rules-only — they produce
stat readouts ("your #1 artist is your #1 artist"), not the human line. The
durable `read` is the cross-domain asset music discovery consumes.

> **Privacy note (deliberate exception):** synthesis and brain chat send compact
> node slices, evidence strings, and limited novelty samples to Anthropic's API,
> not full node snapshots. This is the one place personal data leaves the
> device, and it's an accepted tradeoff for music taste. The API key lives in
> `Info.plist` for dev only; a shipped build points `WormAnthropicBaseURL` at a
> proxy that holds the key (the client swaps with no code change).

## 3. Cardinal rules (non-negotiable)

1. **Every node squeezes everything.** Maximal extraction is a requirement, not
   a nice-to-have. If the API exposes it, we capture it. Half-measures here
   starve the profile.
2. **Everything is persisted, per user.** Connect once, set up forever. We never
   make the user reconnect or re-sync from scratch. Refresh is a *light top-up*
   that only pulls what's new. (DB + top-up not built yet — see backlog.)
3. **First delight is fast and partial.** The first "wow" must land within
   seconds of connecting the *first* node, computed from whatever has synced so
   far. We never wait for a full sync to say something true.
4. **Insights are observed, not summarized.** This is the line between Worm and
   slop. See §4.
5. **Taste drives music, not music alone.** The first use case is music
   discovery, but every populated node must be allowed to affect the pick.
6. **Music discovery is brand-new and real only.** The first use case never
   surfaces something the user already owns, follows, has played, or plausibly
   knows, and never surfaces a track that fails catalog verification. See §6.

## 4. Tone — the anti-slop standard

The worm is **terse, knowing, second-person, and a little provocative.** It
names the user. It says the thing a perceptive friend would say after going
through your library — the observation that makes you go *"…okay, fair."* It is
never a horoscope, never a press release, never a feature list of your own
taste.

The worm is allowed to be a bit cheeky. It is never sycophantic. It does not
congratulate the user on having taste. It notices.

| ✅ Worm | ❌ Slop |
|--------|---------|
| "Not as into rap these days, are you?" | "You enjoy a diverse range of genres including hip-hop!" |
| "You and Phoebe Bridgers go back. Three years, every season." | "Phoebe Bridgers is one of your top artists." |
| "Half your favorites, the average person has never heard of." | "You have eclectic and unique taste in music." |
| "Your heart's still in 2016." | "You listen to music from various decades." |
| "You skip the singles. It's the deep cuts you actually play." | "You listen to a mix of popular and lesser-known tracks." |

Rules of voice:
- One observation per line. Don't stack.
- Prefer the surprising true thing over the obvious true thing.
- Specific nouns (artist, year, genre, place) > adjectives.
- Never explain the data ("based on your top artists…"). Just *know*.
- If it could be said about anyone, it's slop. Cut it.

**Banned constructions** (these read as machine-written; never generate them —
in insights, greetings, copy, anywhere the worm speaks):

- The em-dash. The literal `—`/`–` character is banned; use two sentences. A
  deterministic audit drops any line containing it before it reaches a surface.
- The "not X, it's Y" reframe, in *any* phrasing: "you don't just X, you Y",
  "you're not X, you just Y", "isn't X. It's Y", "X long before Y".
- Clever-for-its-own-sake metaphor or wordplay that needs decoding ("the 70s
  wearing a modern jacket", "passed the Dylan gauntlet"). Plain and observed.
- The rule-of-three list.
- Reciting a number back instead of interpreting it; naming the data source.
- **Guessing.** Never assert anything the data doesn't support — age, who they
  are, what they "would" do. Wrong-but-confident is the worst failure of all.

Lines should be **short** (a spoken aside, under ~14 words) and may be **warm or
light**, not only incisive. This bar is the **taste-profile standard** and the
worm's output contract for *any* query of the brain — not an FTUE detail.

## 5. FTUE — the first five minutes

The whole funnel exists to deliver §3.3 (fast, partial delight). Steps:

1. **Logo.** The worm draws itself in (`WormSplashView`), then hands off to onboarding.
2. **Soft intro, no node.** Onboarding introduces the worm, then asks for a
   selfie and Spotify. It is warm, low-pressure, and already alive.
3. **Connect a node.** Spotify first (richest, fastest to a good insight).
4. **Delight *while* it syncs.** As the node streams data in, the worm surfaces
   what it notices off partial data. The user must feel "it gets me" before the
   sync ever finishes.

**Pacing the reveal.** A few strong observations (target 4–5 for the whole
download), not a dump. The first lands fast and must be real and human. The rest
trickle out, paced, across the entire sync — one is always held back so a reveal
lands right at completion. The run closes on the worm meeting the user by name
("It's nice to meet you, Emilio."). The status under the worm shows live sync
progress the whole time so a gap between insights never reads as a stall.

**Architecture implication for step 4:** the sync must publish insights
incrementally as slices land, not at the end. The cheapest high-signal slice is
`topTracksShort` / `topArtistsShort` (one call each) — the first insight should
fire off that, not wait for the full library, playlists, and recently-played to
finish. The insight engine consumes whatever the node has so far and emits as
soon as a rule's inputs are satisfied.

## 6. First use case — taste-to-music discovery

The first real payoff of the taste profile: **find the user music we *know*
they'll love.**

This is not "music data goes in, similar music comes out." It is the first place
the whole taste profile proves itself by translating identity, aesthetics,
habits, places, media, routines, and listening history into one song.

The hard constraint, which is the entire point:

> It **must** be brand new to them. Not in their library, not an artist they
> follow, not in their play history, not a track they've obviously been served.
> If they already know it, we failed — even if they'd love it.
>
> It must also be real. No exact catalog verification, no surfaced
> recommendation.

Anyone can recommend what's adjacent and familiar. Worm's promise is the
unfamiliar thing that lands. The recommendation engine isn't built yet; when it
is, novelty and catalog verification are preconditions, not ranking tweaks.

### V2 retrieval bar

V1 retrieves memories and lets the model propose. V2 flips that:

1. Build a real candidate pool first from verified catalogs and discovery
   sources.
2. Score candidates against the full taste graph, including non-music anchors:
   visual aesthetics, places, routines, eras, creators, objects, social context,
   moods, and recurring life patterns.
3. Penalize normal-platform obviousness: known artists, high-overlap radio
   neighbors, mainstream popularity, playlist-common tracks, and anything too
   close to surfaced memory.
4. Ask the model to explain/rerank verified candidates only. The model may not
   invent songs.
5. Log why the chosen song won and why the nearest rejects lost.

### Secondary effect nodes

The discovery engine needs derived rabbit-hole structures between raw node data
and candidate songs. A connected node tells us what the user touched; a
secondary effect node tells us what that touch points toward: producer credits,
side projects, labels, scenes, sample sources, live versions, places, routines,
trusted people, visual aesthetics, and other downstream trails.

See `docs/secondary-effect-nodes.md` for scope, tradeoffs, and the implemented
Revision A/B path: typed seeds on every slice, hero journeys as evidence-gated
code (`Worm/Profile/Digging/`), catalog-verified candidate pools, delegated
digging rounds, spend tracking, and route-aware final ranking.

## 7. Insight catalog — instant wins from one node (Spotify)

These are *sketches* to prove the bar, all derivable from data the Spotify node
already captures (`SpotifyNodeSnapshot`). Lines are tone references, **not
copy** — generate fresh, don't ship these verbatim. ⚡ = computable from the
first cheap slice (instant FTUE delight); the rest need more of the sync.

Signals available: top tracks/artists across short/medium/long ranges, each
artist's `genres` + `popularity` + `followers`, track `popularity` + `explicit`
+ `durationMs` + album `releaseDate` + `trackNumber`, saved tracks (`addedAt`),
saved albums (`label`, `releaseDate`), followed artists, recently played
(`playedAt`), playlists (+ hydrated items), profile (`country`, `product`).

1. **Cooling on a genre** ⚡ — a genre's share is high in `long`/`medium` but
   dropping in `short`. → *"Not as into rap these days, are you?"*
2. **New fixation** ⚡ — artist heavy in `short`, absent from `medium`/`long`.
   → *"Somebody's got their hooks in you this month."*
3. **Ride-or-die** — artist present in all three ranges. → *"You and ___ go
   back. Every season."*
4. **The digger** ⚡ — mean `popularity` of top tracks is low (~<35). → *"Half
   your favorites, most people have never heard."*
5. **Stuck in an era** — `releaseDate` years of top tracks cluster on one
   period. → *"Your heart's still in 2016."*
6. **Nostalgist** — almost nothing in heavy rotation is from the last ~5 years.
   → *"Barely anything you love was made recently."*
7. **Deep-cut listener** — top tracks skew to high `trackNumber` / low
   per-artist popularity vs the artist's singles. → *"You skip the singles."*
8. **One-album obsession** — many top tracks share one album. → *"You've been
   living inside one record."*
9. **Genre identity** ⚡ — one or two genres dominate top artists' `genres`.
   → *"It always comes back to ___ with you."*
10. **No lane** ⚡ — top artists span many disjoint genres. → *"You don't have a
    lane, and you like it that way."*
11. **Aspirational library** — many `savedTracks` never appear in any top range
    or recent plays. → *"Your library's full of songs you never go back to."*
12. **Follows, doesn't listen** — `followedArtists` absent from tops/recent.
    → *"You follow ___ but you never actually play them."*
13. **Night owl** — `recentlyPlayed` `playedAt` clusters late. → *"Most of this
    happens after midnight, doesn't it?"*
14. **On repeat** — same track repeated across `recentlyPlayed`. → *"___ again.
    And again."*
15. **Long-form taste** — high mean `durationMs`. → *"You like a song that takes
    its time."*
16. **Era-jumper recency** — `short` top contains decades-old releases. → *"This
    month you went digging in the crates."*
17. **Beyond music** — saved shows / audiobooks present. → *"You're not only
    here for music — ___ has your attention too."*
18. **Curator vs consumer** — many user-owned, hydrated playlists vs few.
    → *"You don't just listen, you build."*

Each insight needs a confidence/threshold before it fires — a wrong "insight"
breaks the entire promise harder than no insight. **Silence beats a miss.**

## 8. Roadmap — now / next / later

**Now (built):**
- Six maximal-extraction nodes: Spotify, Apple Music, YouTube, Contacts, Photos,
  Calendar (Apple Music incl. album tracks and playlist entries; YouTube incl.
  subscriptions, playlists, liked videos, activities, uploads, and video/channel
  enrichment; Contacts incl. groups, accounts, relations, social profiles,
  organizations, dates, communication surfaces, and image data; Photos incl.
  on-device Vision plus AVFoundation video metadata).
- Per-node persistence; connect-once, no auto re-sync.
- A single `WormHomeView`: setup, naming, delivery-time selection, active
  digging, and the daily recommendation reveal are states of the same home.
- A developer node graph is still implemented, but has no active home entry.
- Brain foundation: per-node slices, combined brain context, Claude-backed
  synthesis/query boundary, local novelty checks, and Profile -> Brain Chat.
- Node progression: the engagement loop that drips unlockable brain nodes on a
  countdown, each granting a reward (growth, cosmetic, dormant recommendation),
  gated by a local notification and falling back to a perpetual cooldown. See
  `docs/node-progression.md`.

**Next:**
- Streaming insight engine over the brain slices (Spotify first for §7 instant
  wins), surfaced through the worm during FTUE sync.
- Incremental sync that can publish partial slices to the engine.

**Later (do not build speculatively):**
- Taste-profile model: how nodes map into the profile and how importance is
  weighted. The central design problem.
- Music discovery engine with the brand-new-only novelty filter (§6).
- More nodes (location, messages metadata, health if ever granted, …) — each
  deepens the worm.

## 9. Backlog tasks (written down, not yet started)

- [ ] **Per-user persistent DB.** Move node snapshots from per-file JSON
      (`SnapshotStore`) into a real per-user store. Every field every node
      offers, retained.
- [ ] **Light top-up refresh.** On launch/refresh, check each node for *what's
      new* and append only the delta — never a full re-pull. The user is set up
      after the first connect, permanently.
- [ ] **Insight confidence framework.** Thresholds + a "silence beats a miss"
      gate so the worm never surfaces a weak/ wrong observation.
