# First-run "base" phase, then the drip

Design for the first-time home experience. Splits the node progression into two
phases: a **base** phase (build a foundation, no countdown) followed by the
existing **drip** phase (one node per 24h, countdown header). Adds a user-facing
drip manager to Profile.

## Why

Today the first home entry shows a single drifting apple plus the big "WORM
FOOD" countdown header, and the very first drip step (`apple-music`) is available
immediately. The first thing a new user sees is a clock. We want the first thing
to be an invitation: a few prominent apples to feed the worm a base off, no
timer. The countdown only appears once the base is built.

## Phases

`ProgressionState.Mode` gains a `.base` case, ordered before the existing ones:

```
base → drip → cooldown
```

New installs start in `.base`. Existing installs (already past onboarding) load
whatever mode they persisted; a state with a non-empty `completedEntryIDs` and no
`.base` marker is treated as `.drip`/`.cooldown` as before (see Migration).

### Base phase
- No `nextUnlockAt`, no countdown, no `CountdownHeaderView`.
- The base set is fixed and ordered: `NodeCatalog.baseEntryIDs = ["photos",
  "lock-screen", "ideal-saturday"]`.
- `NodeProgression` exposes the base entries and the pending (unfed) subset:
  - `var baseEntries: [NodeCatalogEntry]`
  - `var pendingBaseEntries: [NodeCatalogEntry]` — base entries not in
    `completedEntryIDs`.
  - `var isBasePhase: Bool { state.mode == .base }`
- Feeding a base apple calls `claim(entry:)` only. **No per-apple countdown, no
  `advance()`.**
- When `pendingBaseEntries` becomes empty (last base apple fed), transition:
  set `state.mode = .drip`, `state.cursor = 0`, and `arm(hours: 24)`. This is the
  first moment a countdown exists.
- Notification permission is requested at this transition (the first real
  countdown), not on first claim as today.

### Drip phase
Unchanged from today: one morsel drifting in, `CountdownHeaderView` visible, each
`claim` → `advance()` arms the next 24h window. Cooldown after the schedule is
exhausted, unchanged.

## Catalog changes

### Two new base prompts
- **`lock-screen`** — photo prompt. title "your lock screen", subtitle "the
  first thing you see", `captureKind: .photo`, `brainNodeID: .prompts`, glyph
  `lock.iphone` (fallback `photo`). Signal: aesthetic + who/what they center
  (people, pets, art → graph).
- **`ideal-saturday`** — text prompt. title "your ideal saturday", subtitle "in
  three words", `captureKind: .text`, `PromptSpec(placeholder: "three words")`,
  `brainNodeID: .prompts`. Signal: routine/vibe.

### Five new banked prompts (drip pool)
Fun prompts generated during design, banked so they're not lost:
- `last-obsession` — text. "the last thing you got obsessed with" / "a show, a
  snack, a rabbit hole".
- `nightstand` — photo. "what's on your nightstand".
- `everyday-order` — text. "your everyday order" / "coffee, drink, whatever you
  always get".
- `window-view` — photo. "the view out your window" / "wherever you are now".
- `room-corner` — photo. "a corner of a room you love".

### Schedule re-author
The base 3 (`photos`, `lock-screen`, `ideal-saturday`) come **out** of the drip
`firstRunSchedule`. Everything else banks in, preserving the cosmetic payouts:
- Remaining sources: `apple-music`, `youtube`, `contacts`, `calendar`.
- Existing prompts: `fit-photo` (→ midnight), `latest-book`, `weekend`,
  `comfort-movie` (→ clay), `bookshelf` (→ moss), `stuck-song`, `last-concert`,
  `desk-now`.
- New banked prompts: `last-obsession`, `nightstand`, `everyday-order`,
  `window-view`, `room-corner`.

Cosmetic distribution (midnight / clay / moss) is preserved on comparable steps.
`cooldownPool` continues to be "everything in the catalog not used by the
schedule and not in the base," derived the same way.

## Home — base phase UI

While `progression.isBasePhase`:
- `CountdownHeaderView` is **not** shown. In its place, one quiet encouragement
  line near the top: e.g. *"feed him all three — that's his base."*
- The 3 base apples render **scattered in the tree canopy** (reusing
  `FoodAppleView` at ~68pt), staggered heights, each gently bobbing (reusing
  `HoverBob`), labeled beneath:
  - upper-left tree ≈ (0.22·W, 0.30·H)
  - upper-right tree ≈ (0.75·W, 0.25·H)
  - lower-center ≈ (0.50·W, 0.40·H)
- Tap any apple → existing feed mechanics:
  - `photos` → real permission connect + sync (`connectSource`).
  - `lock-screen` / `ideal-saturday` → `PromptCaptureView` sheet, then record on
    `PromptNode`.
  - On success: the apple flies into the worm's mouth (existing `gulpAndGrow` /
    `settleGrow`), that apple vanishes, the worm grows a notch. On denial/cancel
    the apple returns, uneaten (same as today).
- When the **last** base apple is eaten: forest beat, header slides in, first
  24h drip countdown arms, first drip morsel begins its normal drift.

The single-drift morsel flow is untouched for the drip phase.

### Feed wiring
`finishUnlock` currently does `claim` + `advance` (+ first-run notification ask).
Split it:
- **Base feed:** `claim(entry:)`, grow, then if `pendingBaseEntries.isEmpty`
  call a new `beginDrip()` (sets `.drip`, cursor 0, `arm(24h)`, requests
  notification permission once).
- **Drip feed:** unchanged (`claim` + `advance`).

## Profile — drip manager (user-facing)

New section, separate from the dev panel:
- Phase chip: *Base* / *Drip* / *Cooldown*.
- Ordered rows: base (3) then the drip schedule. Each row:
  - apple emblem (`FoodAppleView`) + title
  - status: **fed ✓** / **ready now** / **counting down HH:MM:SS** / **upcoming 🔒**
  - the cosmetic that step grants, shown as an earned vs locked swatch.
- The active step shows its live countdown inline (driven by a `TimelineView`
  periodic tick, like `CountdownHeaderView`).

Reads `NodeProgression` (`@Observable`) directly. Status per row derives from:
`completedEntryIDs`, the current `mode`/`cursor`, `availableUnlock`, and
`timeRemaining`.

## Migration

- New `Mode.base` is the default only for genuinely fresh state
  (`ProgressionState()` with empty `completedEntryIDs`).
- On load, if a persisted state predates this change (decodes with no `.base`
  ever set but has progress), it stays in whatever mode it saved — existing users
  don't get dropped back into a base phase. Because `mode` already persists and
  defaults to `.drip`, an old snapshot simply keeps `.drip`; only brand-new
  `ProgressionState()` should default to `.base`. Implement by making the fresh
  initializer set `.base` while the `Codable` default stays `.drip`.

## Testing

Deterministic `NodeProgression` tests (injectable `now`):
- Fresh state starts `.base`, no `timeRemaining`, `pendingBaseEntries` == base 3.
- Feeding base apples one by one: no countdown arms until the third; on the
  third, mode flips to `.drip`, cursor 0, `nextUnlockAt` ≈ now + 24h.
- Drip behaves as before (advance arms next, cooldown after schedule).
- `cooldownPool` excludes base + scheduled entries.
- Migration: a decoded `.drip` snapshot with progress does not revert to `.base`.
```
