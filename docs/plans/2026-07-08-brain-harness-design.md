# Brain harness redesign: dossier → hunt → judge+write

## Why the first insight feels generic

1. **Data poverty.** The model never sees track-level evidence. `SpotifyFeatureExtractor`
   reduces everything to ~15 artist names per range, genre percentages, and playlist
   titles before Claude sees anything. Release dates, popularity scores, rank movement
   between time ranges, saved-at timestamps, and play timestamps are fetched (or fetchable)
   and then discarded. A line that "feels like memory" cannot be written from counts.
2. **One shot.** Notice + verify + write happens in a single structured completion, and
   the picker sorts by the model's self-reported confidence — it grades its own homework.
3. **No world-knowledge crossing.** Uncanny insights come from crossing user data with
   what the model knows about music (which track is the single vs. the album cut, when a
   scene peaked, what liking X-before-Y implies). The harness never asks for it.
4. **Wrong effort.** `BrainSynthesisMode.quick` mapped to effort `"low"` — the
   make-or-break onboarding moment ran at the lowest reasoning setting.

## The harness

Nodes/slices/graph stay. Between slice and surfaced line, every brain pull now runs:

**Stage 1 — Dossier** (`BrainDossier`, deterministic, on-device). An evidence-dense
document with item-level texture: top tracks per time range with rank, release year, and
popularity; artist rank movement across ranges (durable / faded / fresh); deep-cut flags
(track popularity far below artist popularity); saved-track timeline from `added_at`;
recently-played sequence with timestamps and repeats; playlists with sizes and flags.
Attached to `NodeBrainSlice.dossier` so it flows through the existing context plumbing
and persistence.

**Stage 2 — Hunt** (`BrainSynthesizer.hunt`). One high-effort call (two parallel calls
with different lens emphases for `deep` mode) that produces 8–14 *candidate observations*,
not finished lines: claim + cited evidence + angle + an explicit "why this couldn't be
said about a random person". The prompt instructs the model to bring its own music/world
knowledge and cross it against the evidence.

**Stage 3 — Judge + write** (`BrainSynthesizer.judgeAndWrite`). An adversarial pass that
receives the candidates, kills anything generic / not entailed / horoscope-shaped, ranks
survivors, and only then writes the winners in the worm voice under the existing hard
rules. Confidence is assigned by the judge, not the finder.

Effort: first insight (`quick`) runs both stages at `high` (~15–20s total). Profile
synthesis (`deep`) runs parallel hunts at `high` and the judge at `xhigh` — time is
explicitly not a constraint there.

## Recommendation path

`answer()` now asks for a **ranked list of up to 3 candidate recommendations** per model
call instead of one. `TasteProfile.answer` walks the list through the local novelty
filter and catalog verification and surfaces the first survivor; a fresh model call (with
the accumulated rejections) happens only when the whole list dies. Music-recommendation
intents run at `xhigh`.

## Data surface changes

`syncOnboardingTastePreview` additionally fetches the first page of saved tracks (with
`added_at`) and recently played (with `played_at`) when the scopes allow — two cheap
calls that give the first-insight dossier its temporal texture. The background
`syncEverything` still supersedes them.

## v2: the recognition bar (post-first-run revision)

First live run produced: *"You keep one perfect single from each 70s soft-rock
act, never the whole record."* True, specific, evidence-backed — and worthless.
It describes the **shape of the library**, not the person. Postmortem:

1. **Dossier framing leak (root cause).** The dossier's computed section was
   titled "One-song relationships in the all-time record (the song, not the
   artist)" with the editorial aside "often more telling than a whole-artist
   habit." The model paraphrased the section header into the line. Interpretive
   framing in the dossier becomes the insight; the dossier must be neutral fact
   and interpretation must stay in the hunt. All editorial phrasing removed.
2. **Hunt allowed pattern-level claims.** Nothing required a named anchor. v2:
   every candidate must name a specific artist/song/scene/year; claims about the
   person's consumption mechanics (saving, playlisting, singles-vs-albums) are
   banned outright; the lens list is recast as *recognition shapes* (dated
   allegiance, a song that still owns them, a distinction they can hear, a
   buried allegiance, a lineage, a ritual).
3. **Judge's kill test was too weak.** "Couldn't be said about a random person"
   passes library-shape observations. v2 gate is the explicit snob simulation:
   for each candidate the judge predicts the reaction of the proudest-taste
   reader — "how did it know that" survives, "so what, that's my data" dies.
   Each surfaced insight must emit a `snobReaction` field (schema-required),
   forcing the simulation instead of hoping for it. Library-shape and
   no-named-anchor kills are first in the kill list, with the failed line quoted
   as a counter-example.
4. **Free coverage win.** Quick mode ran one hunt pass; passes are concurrent,
   so the first insight now runs both lens sets at no wall-clock cost.

The master prompt gains the cardinal rule: *recognition, not description* — an
observation is about the person, never about the shape of their library.

## Files

- `Profile/BrainDossier.swift` (new) — Spotify + Apple Music dossier builders
- `Profile/BrainModels.swift` — `NodeBrainSlice.dossier`, effort remap, `BrainAnswer.recommendations`
- `Profile/BrainSliceBuilder.swift` — attach dossiers
- `Profile/BrainPromptLibrary.swift` — hunt / judge+write / upgraded query prompts
- `Profile/BrainSynthesizer.swift` — staged pipeline + ranked-candidates answer
- `Profile/TasteProfile.swift` — candidate-walking recommendation loop
- `Nodes/Music/Spotify/SpotifyMusicNode.swift` — richer onboarding preview
