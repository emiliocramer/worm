# Node Progression

## What This Is

Node progression is the engagement loop that makes users *crave* building out
their graph. Every unlock adds a real brain node (a stronger graph means better
recommendations) and lands a reward. The first run is a curated daily drip; once
the script is exhausted it flips to a perpetual cooldown so it never dead-ends.
A countdown header plus a local notification pull the user back.

The mechanism is deliberately simple: one persisted date says when the next node
unlocks. Everything else (the header, the notification, the "available now"
state) is derived from that date by pure comparison. There is no background loop,
no polling, no server.

The design lives in `docs/plans/2026-07-13-node-progression-design.md`. This doc
describes what the **code** actually does, and calls out where the shipped
behavior is simpler than the design (see "Known follow-ups").

## Where It Lives

```
Worm/Progression/
  ProgressionModels.swift   NodeCaptureKind, PromptSpec, CosmeticID, StepReward,
                            ScheduleStep, ProgressionState
  NodeCatalog.swift         static catalog (source + prompts) + firstRunSchedule
  NodeProgression.swift     @Observable owner of time: arm / claim / advance
  UnlockNotifications.swift UNUserNotificationCenter wrapper (UnlockScheduling)
  Cosmetics.swift           CosmeticID -> worm color / eye color / display name

Worm/Nodes/Prompt/
  PromptNode.swift          generic @Observable node for all self-report prompts
  PromptCaptureView.swift   camera / text / choice capture sheet

Worm/App/
  CountdownHeaderView.swift the sliding top-of-home countdown capsule
  WormAppDelegate.swift     UNUserNotificationCenterDelegate (tap + foreground)
  WormHomeView.swift        unlock -> morsel -> feed -> gulp/grow -> reward flow

Worm/Profile/ProfileView.swift   the "Progression (dev)" panel
WormTests/ProgressionTests.swift deterministic unit tests
```

## Concepts

**Node catalog** (`NodeCatalog`). The static, authored list of every node the
worm can ever have. `NodeCatalog.all` is `source + prompts`. Every entry is a
`NodeCatalogEntry` with an `id`, `title`, `subtitle`, `glyph` (SF Symbol),
`captureKind`, an optional `sourceRoute`, an optional `PromptSpec`, and a
`brainNodeID`. To the brain every entry is uniform: it produces slices and grows
the worm. The only difference is *how* it captures.

**Capture kind** (`NodeCaptureKind`).
- `.source`: an existing heavy OAuth/permission node (Apple Music, YouTube,
  Photos, Contacts, Calendar). Its `sourceRoute` drives the real
  `connect` / `syncEverything` path. `brainNodeID` is that node's own id.
- `.photo` / `.text` / `.choice`: self-report prompt nodes. They carry a
  `PromptSpec` (placeholder, options, free-text toggle, char limit) and are
  captured with `PromptCaptureView`. All prompts map to `BrainNodeID.prompts`.

**Progression** (`NodeProgression`, `@MainActor @Observable`). The single owner
of *time*. It holds the persisted `ProgressionState`, a cursor into the schedule,
and the `nextUnlockAt` clock. It exposes `availableUnlock`, `timeRemaining`,
`arm(hours:)`, `claim(entry:)`, and `advance()`. Views only read/observe it. It
persists `ProgressionState` through `SnapshotStore` (`node-progression.json`).

**Schedule step** (`ScheduleStep`). One authored drip step: `entryID`, a
`StepReward`, and `intervalHours` (default 24). The ordered list is
`NodeCatalog.firstRunSchedule`.

**Reward** (`StepReward`). Per-step, each field toggleable:
- `growth` (always true; the worm always grows when fed).
- `insight` (a fresh observed line; see follow-ups: not yet synthesized in the
  feed flow).
- `cosmetic: CosmeticID?` (a worm re-skin; nil = none).
- `recommendation` (**wired but dormant** until the discovery engine exists).

**Gate.** The daily unlock is hard-gated by the countdown: no morsel appears
until `availableUnlock` is non-nil. A separate always-open "connect more" surface
lets eager users add source nodes anytime, ungated and unrewarded.

**Mode** (`ProgressionState.Mode`). `.drip` walks `firstRunSchedule` by cursor.
When `cursor >= schedule.count`, `advance()` flips to `.cooldown`, which offers
`NodeCatalog.cooldownPool` (every catalog entry the schedule never used, prompts
first then sources) on a repeating `cooldownIntervalHours` timer. Cooldown
unlocks reward `insight: true, cosmetic: nil` by default.

## Authoring: add or reorder an unlock

Everything is authored in `NodeCatalog.swift`. Two edits.

1. **Add the entry** to `NodeCatalog.source` or `NodeCatalog.prompts` (part of
   `NodeCatalog.all`):

   ```swift
   // a prompt entry (maps to BrainNodeID.prompts)
   .init(id: "latest-book", title: "the last book you read",
         subtitle: "title's enough", captureKind: .text, sourceRoute: nil,
         prompt: PromptSpec(placeholder: "title, author, whatever you remember"),
         glyph: "book.fill", brainNodeID: .prompts)

   // a source entry (maps to its own node's BrainNodeID, carries a NodeRoute)
   .init(id: "apple-music", title: "your other music",
         subtitle: "connect Apple Music so I hear the rest",
         captureKind: .source, sourceRoute: .appleMusic, prompt: nil,
         glyph: "music.note", brainNodeID: .appleMusic)
   ```

   Source entries set `sourceRoute` and their real `brainNodeID`; all prompts use
   `brainNodeID: .prompts` and set a `PromptSpec` instead of a route.

2. **Place it in the drip** by adding/reordering a `ScheduleStep` in
   `NodeCatalog.firstRunSchedule`. This is where the reward knobs live:

   ```swift
   ScheduleStep(entryID: "fit-photo",
                reward: StepReward(insight: true, cosmetic: .midnight)),
   ScheduleStep(entryID: "latest-book",
                reward: StepReward(insight: false)),
   ```

   `intervalHours` defaults to 24 and can be set per step. An entry that is in
   `NodeCatalog.all` but not in the schedule automatically becomes a cooldown
   offering.

## Timer

No background loop. One persisted `Date` (`nextUnlockAt`); everything derives
from it.

- **Availability** is a pure comparison: an unlock is ready when
  `nextUnlockAt == nil` (ready now) or `now() >= nextUnlockAt`, and there is a
  next entry to offer. `now` is injectable, so tests are deterministic.
- Because nothing polls, an unlock that matured while the app was closed is
  simply *there* when `availableUnlock` is next read on home appear.
- **The visible countdown** ticks via `TimelineView(.periodic:)` once per second
  in `CountdownHeaderView`, reading `timeRemaining`. UI-only. No `Timer`.
- **Arming** (`arm(hours:)`) sets `nextUnlockAt = now + hours` and schedules the
  notification (or cancels it if there is no next entry). `advance()` calls it
  with the step's `intervalHours` (or the dev override).

## Notifications

Local, on-device, no server. Implemented in `UnlockNotificationScheduler`
(`UnlockScheduling`), which the progression owns; a no-op double is injected in
tests.

- One stable identifier, `"worm.unlock"`. Re-arming removes the pending request
  first, so notifications never stack.
- `requestAuthorizationIfNeeded()` asks contextually and only when status is
  `.notDetermined` (options `.alert`, `.sound`); a prior grant or denial is
  respected silently. If denied, the in-app countdown still works.
- Copy is worm-voiced and terse: title `"your worm's hungry"`, body
  `"it wants <entry title>."`
- `WormAppDelegate` is the `UNUserNotificationCenterDelegate`. It presents the
  banner in the foreground and, on tap of a `route == "unlock"` notification,
  posts `.wormUnlockTapped`. `WormHomeView` listens for that and presents the
  waiting morsel.

## Rewards and cosmetics

- **Growth** is driven by `WormHomeView.earnedSize`, which stretches the worm
  from `progression.state.completedEntryIDs.count` (plus populated slice count
  and insight count). Each claimed unlock permanently grows the worm.
- **Cosmetics** (`CosmeticID`: `midnight`, `clay`, `moss`, `paperInverse`) map to
  a worm body `color` and `eyeColor` in `Cosmetics.swift`. `claim` records the
  cosmetic in `earnedCosmetics` and sets it as `activeCosmetic`; `WormHomeView`
  reads `activeCosmetic?.wormColor` / `.eyeColor` to re-skin the worm.
- **Recommendation** is present in `StepReward` but never fires. It stays dormant
  until the discovery engine exists (its own later timer system) and is not set
  on any current schedule step.

## Home flow

The whole sequence is one choreographed run in `WormHomeView`, reusing the
onboarding morsel grammar (drift in, hover, tap to feed, gulp, grow, caption):

1. `CountdownHeaderView` sits pinned at the top. Locked, it shows
   `"next node in 4h 12m"` with a depleting track. Available, it fills to ink,
   pulses, and reads `"a new node unlocked"`.
2. Tapping the available pill (or a tapped notification, via `.wormUnlockTapped`)
   calls `presentNextMorsel()`, which reads `progression.availableUnlock` and
   floats the morsel to the hover spot with a "tap to feed" hint.
3. **Feed.** `.source` entries gulp, then run the real
   `connect` / `syncEverything` for that `NodeRoute`. `.photo/.text/.choice`
   entries present `PromptCaptureView` first; the answer is recorded on
   `PromptNode`, then the gulp runs.
4. Gulp + grow (`gulpAndGrow` / `settleGrow`) plus a `digestCaption`.
5. `finishUnlock(entry)` calls `progression.claim(entry:)` (records completion,
   sets any cosmetic, shows an `"unlocked: <name>"` caption for cosmetics) then
   `progression.advance()`, which arms the next countdown. The header slides back
   to locked.

If a source connect is denied or fails, nothing is claimed and nothing advances:
the worm settles back to its prior size, a `"maybe later."` caption shows, and
the ask returns another day.

## Dev panel

Profile has a "Progression (dev)" section behind `DevFlags.showProgressionDevPanel`
(`ProfileView.progressionDevSection`):

- Live readout: cursor, mode, next unlock, completed count, active cosmetic,
  earned cosmetics.
- **Unlock now** (`forceUnlockNow`), **Advance step** (`advance`),
  **Reset progression** (`reset`), **Jump to cooldown** (`jumpToCooldown`).
- **Fire test notification (5s)**: schedules a throwaway notification 5 seconds
  out through the dev scheduler.
- **Fast-forward next arm**: real / 10s / 60s, setting
  `devIntervalOverrideHours` so the next `advance` arms a short interval and the
  countdown can be watched in seconds.
- **Preview cosmetic**: `applyCosmetic(_:)` reskins the home worm to any
  `CosmeticID` (or none) for preview.

## For agents

- The authoring surface is `NodeCatalog.swift`. Adding or reordering an unlock is
  entry + schedule step there; you should not need to touch `NodeProgression`.
- `NodeProgression` owns time and is the only writer of `ProgressionState`.
  Views read it; they never mutate the clock directly.
- Prompt capture never needs a bespoke manager: `PromptNode` is generic and keyed
  by `entryID`, and `PromptCaptureView` renders `.text/.choice/.photo` from the
  entry's `PromptSpec`.
- Deterministic unit tests live in `WormTests/ProgressionTests.swift` (injectable
  `now`, no-op scheduler).

## Known follow-ups (not built)

- **Rich insight reveal on reward.** The design called for a fresh observed
  insight rendered in `FirstInsightReveal` style when `reward.insight` is true.
  The shipped feed flow does not synthesize an insight: the reward is the growth,
  the caption, and the re-armed countdown. `StepReward.insight` is authored and
  recorded but not yet consumed by `finishUnlock`. Wiring a synthesis call from
  the feed flow is the main remaining piece.
- **On-device vision read for photo prompts.** `PromptNode.recordPhoto` stores
  empty `visionKeywords` and the captured image is not persisted;
  `PromptCaptureView` yields the `UIImage` but `submitCapture` records no
  keywords. The design's `SelfieVisionReader` read is not yet wired.
- **The dormant recommendation reward.** `StepReward.recommendation` exists but
  never fires; it waits on the discovery engine and its own timer system.
</content>
</invoke>
