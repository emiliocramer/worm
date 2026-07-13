# Secondary Effect Nodes

## What This Is

Secondary effect nodes are the downstream things a user's raw data points to.

Primary nodes are permissions and accounts:

```text
Spotify, Apple Music, YouTube, Photos, Calendar, Contacts
```

Secondary effect nodes are the rabbit holes inside them:

```text
artist -> producer -> side project -> label -> session player -> scene
video creator -> topic -> aesthetic -> subculture -> music context
photo place -> city -> local scene -> venue -> regional sound
calendar routine -> time of day -> listening use case -> record shape
contact/family signal -> trusted person -> remembered genre -> inherited taste
```

The important shift:

```text
Worm is not searching songs.
Worm is searching consequences.
```

The raw brain says what the user touched. Secondary effects say where that touch
can lead.

## Why We Need It

The current music promise is taste -> music. That cannot mean "more tracks like
your top tracks." The digging sources show that good discovery often comes from
one step sideways or backward:

- a producer credit opens a band the user ignored
- a side project explains an artist without using the obvious hits
- a sample points back to an older source record
- a city or store context changes what feels findable
- a live version carries something the studio track does not
- a missed album period becomes the right gap to search
- a family/DJ/store/person thread becomes the real discovery path

Without secondary effects, Worm can only retrieve the user's existing facts and
ask a model to leap. That encourages obvious adjacency or invented lore.

With secondary effects, Worm gets an explicit route:

```text
brain signal -> seed -> downstream trail -> candidate pool -> novelty filter -> catalog verification -> one song
```

## Revision A (implemented)

The first draft of this doc had a V0 that was honest about its limits and
therefore weak: local-only "route hints" handed to the model, with the real
digging deferred to a V1 enrichment service. Reading the actual code surface
showed the draft glossed over three things, and fixing them makes V0 far
stronger than "hints":

### Fix 1 — seeds come from the structured layer, not from slices

The draft said `BrainTrailBuilder` consumes `BrainContext`. But
`NodeBrainSlice` is prose: summary, facts, evidence, chunks, dossier are all
strings. Extracting typed entities from text we flattened one step earlier is
backwards.

The revision: seed extraction happens where slice building happens — against
the node managers' typed collections (`SpotifyTrack`, `SpotifySavedAlbum`,
`YTVideo`, `PhotoAlbumItem`, `CalendarEventItem`, …) — and the slice *carries*
its seeds the same way it carries its dossier:

```text
NodeBrainSlice.seeds: [BrainSeed]?   // structured, persisted with the slice
BrainContext.allSeeds                // the trail builder's real input
```

`BrainSeedExtractor` is deterministic and on-device, sibling to
`SpotifyFeatureExtractor` and `BrainDossier`. Old persisted slices decode fine
(the field is optional, like `dossier`).

### Fix 2 — the catalog search we already have IS a local digging tool

The draft treated "no external enrichment" as "no candidate pool, hints only."
But the app already talks to two catalogs: `SpotifyWebAPI.searchTracks` and
`MusicCatalogSearchRequest`, used today only to verify a finished pick.
Spotify's search syntax supports field filters — `label:"Impulse!"`,
`year:1968-1976`, `genre:"spiritual jazz"` — and returns full track objects
with popularity, release dates, and URLs.

That flips the pipeline. Instead of

```text
retrieve memories -> Claude proposes a song -> verify it after the fact
```

a music-recommendation pull now runs

```text
seeds -> effect nodes -> trails
      -> dig queries (deterministic + model-proposed)
      -> Spotify catalog search (real tracks only)
      -> local novelty + junk + obviousness filters
      -> verified candidate pool
      -> Claude ranks the pool and explains through the route
```

Claude never invents a candidate. Every track in the pool came out of a real
catalog response and already survived the novelty memory before the model sees
it. Verification stops being a post-hoc gate that mostly fails and becomes the
front door.

The division of labor is the one this doc always wanted:
**the model may propose trails and queries; only the catalog promotes them to
facts.** A hallucinated search query costs one empty response. A hallucinated
song costs the product's promise.

### Fix 3 — journeys are code, and unprovable journeys stay dormant

Hero journeys lived only in markdown. Now `HeroJourney` is an enum whose cases
carry evidence predicates over typed seeds. A journey activates only when the
local data can actually prove its brain signal:

- Diggable now: The Missed Chapter (label/era gaps around durable artists),
  The Cheap-Risk Bin (low-popularity listening), The Local Oddity (place
  seeds), The Live Room (live-signal seeds), The Album-First Dig (album-heavy
  libraries), Source DNA / The Context Flip (sample-culture genres, dug as
  year-shifted searches), The Ignored Online Crate (YouTube-heavy taste),
  The Texture Route (texture/aesthetic terms), One Record For Right Now
  (routine seeds).
- Dormant until enrichment: The Closed Door Artist and The Human Curator
  Thread need producer/side-project/person-to-music relations no local source
  proves. Their cases exist, their scores are hard-zero, and the comment says
  why. No local data, no journey — the anti-slop rule applied to routes.

### The known-artist collision, decided

Three journeys (Closed Door Artist, Missed Chapter, Live Room) naturally
produce candidates by or adjacent to known artists, and the vision doc's
cardinal rule says the surfaced artist must be brand new. This collision was
flagged as "revisit later"; later is a bug. Decided now, typed now:

- `BrainTrail.noveltyPolicy` exists and is `.strict` — the only case — so the
  policy is a visible, logged property of every trail, not an implicit
  behavior.
- The Missed Chapter digs the *gap around* the obsession — the label's other
  signings in the neglected years, the scene's adjacent records — never the
  known artist's own catalog. The same-artist variant (late albums, live
  cuts) requires a new `NoveltyPolicy` case and a deliberate vision-doc
  amendment; the enum is where that change will be made, on purpose.

### What still waits for V1 enrichment

Producer credits, session players, side projects, sample lineage. The
`SecondaryEffectType` enum in code contains only locally provable relations
(`labelCatalog`, `eraGap`, `genreScene`, `placeScene`, `routineUseCase`,
`creatorLens`, `textureRoute`). Credit-shaped cases arrive with MusicBrainz,
not before — an effect node that can't cite local evidence may not exist.

### Implementation map

All new code lives in `Worm/Profile/Digging/`; the brain boundary is
unchanged (only `BrainSynthesizer` talks to Claude).

```text
DiggingModels.swift      BrainSeed, SecondaryEffectNode, BrainTrail,
                         CatalogDigQuery, DugCandidate, DigResult, NoveltyPolicy
BrainSeedExtractor.swift typed seeds from node managers; slices carry them
HeroJourneys.swift       HeroJourney enum + evidence predicates
BrainTrailBuilder.swift  seeds -> effect nodes -> ranked trails + deterministic queries
BrainDigger.swift        trails -> model-proposed queries -> catalog search ->
                         novelty/junk/obviousness filters -> DigResult
```

Touched existing code:

```text
SpotifyMusicNode         searchCatalogTracks(query:limit:) — generalized from
                         the verify path
BrainSynthesizer         proposeDigQueries(...); answer(...) takes DigResult
BrainPromptLibrary       dig-query prompt; route-aware recommendation prompt
BrainRetriever           classifyIntent exposed for the pre-model dig decision
BrainModels              NodeBrainSlice.seeds, BrainRetrievedContext.trails
TasteProfile             digs on musicRecommendation intent before answering;
                         pool-matched picks are verified by construction
ProfileChatView          constructs the digger from the nodes it already holds
InsightLog               records seeds/trails/queries/pool/rejections per dig
```

Failure behavior is honest: no Spotify auth, no seeds, or an empty pool means
the dig attaches nothing and the pull falls back to the previous
propose-then-verify path. Apple Music remains a verification source; its
search has no field filters or popularity data, so it does not build pools in
this revision.

## Revision B (implemented) — The Delegated Deep Dig

Revision A made the dig real. Revision B makes it *deep*, and it makes depth
affordable. Three commitments, in priority order:

1. **Quality cannot degrade.** The taste-critical judgment — ranking the
   shortlist and voicing the pick — stays on the strongest model at the
   deepest effort. Every local gate (novelty, catalog verification by
   construction, junk filters) is untouched. Cheap models only ever do work
   whose failure is recoverable.
2. **More digging per recommendation.** Revision A digs one round:
   seeds -> queries -> pool -> pick. Revision B digs in *rounds*: what comes
   back from the catalog becomes new seeds, and the system keeps digging
   sideways and backward until the pool clears a quality bar or the money
   budget runs out. Less "source -> recommendation", more expedition.
3. **Cheaper than Revision A**, despite 5-6x the model calls, by routing each
   call to the cheapest model that can do that job. The constraint is cost
   per unit of digging, never wall-clock time. A pull is allowed to take
   minutes.

### Why one-round digging is shallow

The trace from the first live runs shows it: the KPM query came back with
Alan Hawkshaw, Keith Mansfield, Brian Bennett, John Cameron — a *label
roster*, sitting right there in the catalog response. Revision A throws that
structure away; it filters tracks and stops. A human digger would do the
obvious next thing: pull the thread. Hawkshaw and Mansfield point at De Wolfe
and Bruton; the 1969-1977 cluster points at adjacent years; the roster
co-occurrence points at a scene. That next hop is **second-level digging**,
and it needs no enrichment service — every fact in it came out of a real
catalog response.

### Second- and third-level effect nodes

`SecondaryEffectNode.depth` becomes load-bearing, and `EffectProvenance`
gains its first non-local honest value:

- **Depth 1, `localNodeData`** — derived from the user's own data
  (Revision A, unchanged).
- **Depth 2, `catalogSearch`** — derived from round-1 catalog responses:
  a label roster (artists co-occurring under one `label:` query), an era
  cluster in the results, an artist appearing across multiple trails. These
  are *facts the catalog stated*, not model assertions — the same
  promote-by-evidence rule as everything else.
- **Depth 3, `catalogSearch`** — one more hop, only for high-confidence
  music trails (per the depth tradeoff above), only while budget remains.

The Closed Door Artist and Human Curator Thread stay dormant — producer
credits and person-to-music links still have no provable source. But
label-roster, era-network, and scene-adjacency trails now genuinely deepen,
which is most of what V1 enrichment was going to buy, for free.

### The expedition loop

```text
round 0 (free, local):  seeds -> trails -> deterministic queries
repeat while (pool below quality bar) and (budget remains) and (round < 3):
  SCOUTS    propose 1-3 queries per trail            [Haiku, low,  parallel]
  DIG       run queries against Spotify catalog       [free]
  ASSAYERS  grade results: fame check, junk beyond    [Haiku, low,  parallel]
            heuristics, fit hints; EXTRACT LEADS
            (rosters, era clusters, co-occurrence)
            -> depth-2/3 effect nodes + new seeds
  FOREMAN   read assayed pool + leads + spend ledger; [Sonnet, medium]
            decide: enough, or which leads to chase
            next round, or stop for budget
final:
  SHORTLIST score assayed pool vs compact taste       [Sonnet, high]
            brief -> top 5-7 with route reasons
  JUDGE     rank shortlist, pick 3, voice the answer  [Opus 4.8, xhigh]
            (prompt is small: shortlist + read +
            insights, never the raw pool or the
            full retrieval dump)
```

The foreman's stopping rule is explicit and logged: pool quality bar =
at least N candidates (default 12) with assay score above threshold,
spread over at least 2 trails. Not met and budget left -> chase the
highest-value leads. Budget exhausted -> proceed to shortlist with what
exists. Nothing at all -> Revision A's honest fallback, unchanged.

**Why this can't degrade quality.** Each cheap-model failure mode is
bounded: a bad scout query costs one empty catalog response; a wrong assay
grade demotes a candidate that the shortlist can still rescue; a lazy
foreman stops early and we surface from a pool no worse than Revision A's.
The only unrecoverable judgment — which song, and why, in the worm's voice —
never leaves Opus at xhigh. The judge's prompt actually *improves*: ranking
a graded shortlist is the explicit, only task, which also removes the
zero-candidate refusals Revision A retries around.

**The fame check fixes a real Revision A hole.** Novelty is data-only, so
Grace Jones and Cameo passed into the pool. An assayer explicitly asks "is
this artist plausibly world-famous even though absent from this user's
data?" and grades accordingly — a Haiku-sized question that data alone
cannot answer.

### Model routing and the price table

Prices per MTok (input/output), from the current API price list; cache reads
bill ~0.1x input, cache writes 1.25x:

| Role      | Model            | $/MTok in/out | Why this tier suffices |
|-----------|------------------|---------------|------------------------|
| Scouts    | claude-haiku-4-5 | 1 / 5         | Query synthesis from a single trail + tiny brief; failure = empty response |
| Assayers  | claude-haiku-4-5 | 1 / 5         | Structured grading + entity extraction over catalog rows; mechanical |
| Foreman   | claude-sonnet-5  | 3 / 15        | Budgeted decision over graded data; needs judgment, not taste |
| Shortlist | claude-sonnet-5  | 3 / 15        | Scoring against the taste brief; the judge re-ranks anyway |
| Judge     | claude-opus-4-8  | 5 / 25        | The pick and the voice. Never routed down. |

Cost math, estimated against the live traces:

- **Revision A today**: 1 Opus query-proposal (~3k in / 2k out) + 2 Opus
  xhigh answer calls with the full retrieval dump + pool (~14k in / 5k out
  each) ≈ **$0.46 per pull**, one round of digging.
- **Revision B**: 4 scouts + ~4 assayers + 2 foreman rounds (Haiku/Sonnet,
  ~35k in / 10k out combined ≈ $0.09) + shortlist (~6k/1.5k ≈ $0.04) + one
  Opus judge on a small prompt (~5k/4k ≈ $0.13) ≈ **$0.26 per pull**, two
  to three rounds of digging and no retry tax.

Roughly half the cost for triple the digging. The budget ceiling (default
$0.35/pull, dev-configurable) is enforced in code: the foreman sees the
ledger and remaining budget each round, and the expedition hard-stops at the
ceiling. Raising the ceiling buys more rounds, linearly — cost scales with
digging, not with time.

**Prompt-cache assist.** The compact taste brief + stable system prompt is
shared across every scout/assayer call in a pull; with a `cache_control`
breakpoint it bills once and reads at 0.1x thereafter (caches are per-model,
so the Haiku fleet shares one entry, Sonnet another). The judge's system
prompt is stable across pulls and across the retry, same win. Fast mode
(premium-priced) stays exactly where latency is product-critical — the FTUE
first insight — and is never used in the dig, where time is explicitly not a
constraint.

### Spend tracking — under the hood, per call

`ClaudeClient` starts returning what the API already sends: the `usage`
block (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`,
`cache_read_input_tokens`). Every call produces a record:

```text
ModelCallRecord {
  stage        "scout:contextFlip" | "assay:r2" | "foreman:r1" | "shortlist" | "judge"
  model, effort, speed
  inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens
  costUSD      // computed from the price table above
  durationMs, startedAt
}
```

A per-pull `SpendLedger` aggregates records; it rides `BrainAnswer` (so it
persists with the chat message) and streams into the live trace as each call
completes ("assay:r2 haiku 4.1k→1.2k $0.010 in 6.8s"). The Under the Hood
view gains a **Spend** section: one row per call (stage · model · tokens ·
cache · $ · duration), totals in the pipeline capsules
("11 calls · 96k→18k · $0.24"), and the dig log records why the expedition
stopped (bar met / budget ceiling / round cap). The same ledger covers
synthesis and insight calls, so every model interaction in the app becomes
priced and visible.

### Data model deltas

```text
SecondaryEffectNode.depth      now written honestly (1/2/3)
EffectProvenance.catalogSearch now produced (depth-2/3 nodes)
DigLead                        carries derived catalog threads from assayers;
                               provenance lives on promoted SecondaryEffectNode
DugCandidate                   gains assayScore, fameFlag
DigResult                      gains rounds, leads, ledger, stopReason
BrainAnswer                    gains ledger (spend), already has dig/trace
DigMemory (new snapshot)       winning trails + graded leads persist per user,
                               so the next expedition starts from round 1
                               knowledge instead of re-discovering it (this is
                               V2's "learn from outcomes", pulled forward
                               because it makes every future dig cheaper)
```

### Sequencing

1. **Ledger first** (client usage capture, price table, Spend UI) — it
   instruments Revision A as the baseline and proves the cost claims.
2. **Split the judge** (shortlist stage + small-prompt Opus judge) — the
   quality-critical refactor, measurable against baseline immediately.
3. **Delegate the scouts/assayers to Haiku** — the big cost cut.
4. **The expedition loop + leads + depth-2 nodes** — the big digging gain.
5. **DigMemory persistence** — compounding cost reduction.

Each step ships behind the same honest-fallback rule as Revision A: any
stage failing routes back to the previous revision's path, logged.

### Non-goals for Revision B

- No external metadata sources (still V1 enrichment's job; depth-2 catalog
  facts deliberately shrink what enrichment must add).
- No latency work. If a deep pull takes four minutes and costs $0.26, that
  is a better product than a fast pull that costs $0.46 and digs once.
- No graph UI for effect nodes; depth-2/3 nodes stay brain-only until they
  earn surface area, per the original visibility rules.

## Revision C (implemented) — More Journeys, Real Stories, Variety Pressure

Three consecutive live pulls surfaced soul-adjacent picks through the same two
journeys. The skew had three identifiable sources, all fixed here:

1. **The journey gate was too narrow.** Only 2 of 12 journeys ever activated
   for this profile, both keyed on the substring "soul" in one genre tag, and
   an unmatched profile would produce zero trails and silently skip the
   expedition entirely.
2. **The signal layer under-read the data.** Playlists literally named after
   artists (the loudest devotion signal there is) and photo albums titled
   after places ("Mexxiiicooooo") produced no seeds at all.
3. **Memory only reinforced winners.** `journeyWins` boosted the last
   successful route with no counterweight — a rich-get-richer loop.

### Six new journeys from real, sourced digging stories

`docs/digging-journeys/008-012` are new sourced entries (Chino Moreno's
Team Sleep/Crosses side doors and Aphex Twin's alias tree; Metro Boomin's
producer-to-artist chain; Lori McKenna behind "Humble and Kind"; the Real Rock
riddim's hundreds of versions; SAULT's anonymous drops — each with citations).
They distill into journeys 13-18 in `hero-journeys.md` and six new
`HeroJourney` cases:

- **The Alias & Side Door** — gated on the new `devotion` seed type: a
  playlist named after an artist. Follow the person out of the band.
- **The Producer Chain** — gated on producer-culture genres (trap, drill,
  grime, …). Follow the beat tag into the producer's own records.
- **The Songwriter's Shadow** — gated on country/folk/singer-songwriter.
  Follow the writing credit into the writer's own catalog.
- **The Version Chain** — gated on reggae/dub/dancehall. Walk the riddim.
- **The Anonymous Drop** — gated on the crate-digger signal. Releases that
  evade the promo machine.
- **The Open Crate** — the floor: barely clears the bar whenever seeds exist,
  so the expedition ALWAYS runs and every evidenced journey outranks it. The
  gate can no longer zero the whole system.

These journeys carry no deterministic queries of their own (their relations
are world knowledge); they exist to hand the scouts a route worth walking —
the model proposes, the catalog promotes, exactly as before.

### New seeds

- **Devotion** (`SeedEntityType.devotion`): playlist titles matched against
  artist names by normalized equality, on Spotify and Apple Music.
- **Photo-album places**: album titles collapsed of letter runs and matched
  against a conservative country/scene-city list ("Mexxiiicooooo" -> Mexico).
  This is what finally connects the Mexico thread the read keeps naming.

### Variety pressure (the anti-skew mechanics)

- `DigMemory` now records `recentJourneys` and `recentPicks` (last 5 each) on
  every surfaced pick.
- Trail ranking takes a `journeyBias`: +0.05/win (capped) as before, and
  **-0.08 per recent appearance** — the penalty outweighs the boost, so a
  route that just won must be meaningfully better than the field to run again
  immediately.
- The shortlist and judge prompts receive the recent picks with an explicit
  instruction: repeating the same artist, scene, or genre as the last few
  picks must clear a much higher bar than opening a new corner.

### More digging

`maxTrails` 4 -> 5, `maxRounds` 3 -> 4. The budget ceiling is unchanged at
$0.35 — the delegated tiers are cheap enough (a full scout+assay+foreman round
runs ~$0.02-0.05) that depth comes from routing, not from spending more.

### C.1 — journeys as vocabulary, three more sourced routes

Follow-up to the "how hard are we leaning on the hardcoded journeys" audit:

- **Idiom menu (the vocabulary demotion).** Every journey now carries a
  one-line `idiom`. The Open Crate scout and the foreman receive the full
  menu, so every digging move is available to every profile even when its
  evidence gate did not fire. Idioms are moves, not claims — the anti-slop
  gates still apply to anything factual. Future journeys are one doc entry,
  one enum case, and an idiom line; gating logic is optional priority, not
  the door.
- **Three new sourced journeys** (docs 013-015, hero-journeys 19-21):
  The Diaspora Thread (cumbia rebajada / Sonido Dueñez — heritage genres,
  place-assisted), The Split & Demo (hardcore split/demo format culture —
  DIY genres), The Interpretation Chain (Gould's two Goldbergs — classical,
  the performer-as-discovery inversion).
- **One journey deliberately not shipped:** a dance-music "B-Side Flip" had
  no specific sourced story behind it. No source, no journey — the same rule
  effect nodes live by.
- The remaining ceiling is the seed vocabulary, not the journey count: a
  journey can only gate on signals a node actually extracts. New nodes
  (YouTube, media, location) widen the reachable journey set more than new
  journey entries do.

## Terms

### Seed

A directly observed thing from a primary node.

Examples:

- Spotify top artist: "The Black Keys"
- Apple Music saved album label: "Impulse!"
- YouTube liked creator: a music-production channel
- Photo location: Brooklyn
- Calendar pattern: late-night work blocks

Seeds must be evidence-backed. In code: `BrainSeed`, extracted from typed node
data, persisted on the slice.

### Secondary Effect Node

A derived entity or relation produced from one or more seeds.

Examples:

- "Impulse! -> the label's catalog outside the user's library"
- "top tracks cluster 1996-2004 -> the neglected years around the cluster"
- "Brooklyn photos -> local record-store / scene trail"
- "late-night work blocks -> long-form / meditative record shapes"

Effect nodes are not raw facts unless the source proves them. They carry
confidence and provenance (`localNodeData` in this revision; `catalogSearch`,
`metadataEnrichment`, `userConfirmed` reserved).

### Trail

An ordered rabbit-hole path that Worm can follow, with the concrete catalog
queries that walk it. In code: `BrainTrail`, including `digQueries`,
`noveltyPolicy`, evidence, and confidence.

### Hero Journey

A reusable digging pattern from `docs/digging-journeys/hero-journeys.md`,
now the `HeroJourney` enum. Journeys choose the kind of trail; effect nodes
provide the actual entities inside it.

## Where It Fits

```text
RAW NODES
-> NODE BRAIN SLICES (+ typed SEEDS)
-> SECONDARY EFFECT NODES
-> TRAILS (hero journey + dig queries)
-> CATALOG DIG (real tracks, novelty-filtered)
-> VERIFIED CANDIDATE POOL
-> CLAUDE (rank + route explanation)
-> WORM
```

This lives inside the brain layer, not the visible graph. A trail becomes
graph-visible only after it proves useful, gets surfaced, or the user asks
"why this?".

## Usage

### Recommendation

1. Classify the query as music discovery (`BrainRetriever.classifyIntent`).
2. Take seeds from the current `BrainContext` slices.
3. Build effect nodes and rank trails against active hero journeys.
4. Emit deterministic dig queries; ask the model for additional query
   hypotheses (queries, never songs).
5. Run every query against Spotify catalog search.
6. Filter: known tracks/artists/albums, junk (karaoke/tribute/covers),
   popularity ceiling, per-artist cap.
7. Hand the surviving pool to the model to rank and explain through the route.
8. Surface the winner with one terse route sentence; full trail in debug.

### Insight Generation

Secondary effects can also produce non-recommendation insights, but only after
the evidence is strong, e.g. repeated trails through the same label or place.
Not built in this revision.

### Graph

Effect nodes are hidden by default. They become visible when they explain a
surfaced recommendation, the user asks to see the dig, or the same trail
recurs across sources. Not built in this revision.

## V1 Scope — controlled enrichment

Unchanged in intent: a server-side enrichment service over MusicBrainz (first),
then Discogs / sample databases after API-terms review. Enrichment results are
cached by entity with provenance and freshness. Enrichment is what activates
the dormant journeys (Closed Door Artist, Human Curator Thread) and the
credit-shaped effect types (producerCredit, collaborator, sideProject,
sampleSource).

## V2 Scope — durable trails

- Persist trails that lead to accepted recommendations.
- Suppress trails that repeatedly fail novelty or catalog verification.
- Learn which hero journeys work for the user.
- Show selected trails in the graph after they earn their place.
- Let the user ask "why this path?" or "dig this way again."

## Tradeoffs

### Persisted Nodes vs On-Demand Trails

Derive on demand, persist only winning or repeated trails. (Seeds persist with
slices because they are cheap and factual; trails do not persist yet.)

### Depth

- depth 1 for weak signals
- depth 2 for normal trails
- depth 3 only for high-confidence music-credit trails (V1+)

### Model Reasoning vs Verified Metadata

The model proposes trail hypotheses and search queries. Only catalog responses
promote candidates to facts. The model never asserts music metadata the pool
does not contain.

### Explaining The Route

One terse route sentence in Worm voice on the surface; the full trail, queries,
pool, and rejections in the debug block and the brain log.

### Non-Music Nodes

Photos, Calendar, Contacts, and YouTube choose and rank routes; music catalogs
choose the final playable song. Worm never says it "dug through" private
non-music data — private signals rank the route, music-safe evidence explains
the pick.

## Failure Modes

- Fake credits: prevented structurally — no credit-shaped effect types exist
  locally, and candidates only come from catalog responses.
- Obvious adjacency: popularity ceiling, per-artist cap, and known-artist
  rejection on the pool; trails that only produce known music produce nothing.
- Novelty failure: the pool is novelty-filtered before the model ranks it.
- Privacy creep: route explanations use music-safe evidence only.
- Graph pollution: nothing digging produces is graph-visible.
- Over-deep traversal: depth capped at 2 locally.
- Empty digs: honest fallback to the previous propose-then-verify path, and
  the dig log records why the pool was empty.

## Design Decisions (resolved)

1. Hidden brain-only structures first? **Yes — implemented that way.**
2. Persist trails from day one? **No. Seeds persist on slices; trails are
   derived per pull until V2.**
3. External enrichment sources for V1? **MusicBrainz plus catalog search
   first; Discogs/sample databases after terms review.**
4. Trail depth? **Default 2. Depth 3 only for verified credit trails (V1+).**
5. Can a non-music node dominate the route? **Yes — place/routine/creator
   seeds rank trails — but the candidate still clears novelty and the
   explanation stays music-safe.**
6. Known artists as absolute rejects? **Yes, and now typed: every trail
   carries `noveltyPolicy: .strict`. Relaxing it for side-project/live-version
   cases requires adding an enum case and amending the vision doc, not
   loosening a filter.**
7. How much route does the user see? **One short reason on the surface; the
   full route in the debug block and brain log.**
8. Does Worm say it "dug through" private data? **No. Private data ranks,
   music evidence explains.**
