# Node progression — design

> The engagement loop that makes users *crave* building out their graph. Every
> unlock adds a real brain node (a stronger graph → better recommendations) and
> lands a reward. A curated daily drip for the first run, then a perpetual
> cooldown so it never dead-ends. Countdown header + local notifications pull
> the user back.

Status: design approved 2026-07-13. Implementation not yet started.

## Why this exists

Worm's growth loop is **more nodes + more permissions ⇒ a smarter worm** (see
`docs/vision.md` §2). Today nothing *pulls* the user back to add the next node.
This system turns graph-building into a paced, rewarded ritual:

- The worm visibly grows every time it's fed (already true).
- A fresh observed insight lands right after feeding (the dopamine).
- Occasional cosmetics (worm skins/accents) are collectible.
- A recommendation-unlock reward type is wired but **dormant** until the
  discovery engine exists (§6 of the vision, a "Later" item).
- A hard-gated daily countdown + push notification creates the return habit.

## Mental model

One new concept: a **progression** that drips **catalog entries** to the user on
a schedule, each granting **rewards**.

```
NODE CATALOG (static, authored)  ─┐
                                  ├─►  PROGRESSION (owns time)  ─►  HOME UI
SCHEDULE (ordered steps + reward) ─┘         │                        (countdown
                                             ▼                         header +
                                     ProgressionState (persisted)      feed/reward)
                                             │
                                             ▼
                                   LOCAL NOTIFICATION (armed at nextUnlockAt)
```

- **Node catalog** — the static authored list of every node the worm can ever
  have. Uniform to the brain (all produce slices, all grow the worm); each
  declares a **capture kind** for *how* it collects.
- **Progression** — the engine that owns *time*: the schedule, a cursor, and the
  timestamp the next unlock arms. Phase 1 is the curated drip; when the schedule
  is exhausted it flips to **cooldown mode** and offers remaining catalog entries
  on a repeating timer.
- **Reward** — attached per schedule step, each field toggleable.
- **Gate** — the daily unlock is hard-gated by the countdown. A separate
  always-open "connect more" surface lets eager users add real source nodes
  anytime, ungated and unrewarded (matches the always-available Apple Music
  morsel already on home).

## Capture kinds

Every catalog entry is a brain node. The only distinction is how it captures:

| Kind | How it captures | Examples |
|---|---|---|
| `.source` | Existing heavy OAuth/permission node | Apple Music, YouTube, Contacts, Photos, Calendar |
| `.photo` | Snap a picture (on-device Vision read) | "photo of your fit", "snap your bookshelf" |
| `.text` | One short free-text answer | "latest book you read", "what'd you get up to this weekend" |
| `.choice` | Pick from options (+ optional free text) | "go-to comfort movie" |

`.photo/.text/.choice` are new **prompt nodes**. They reuse the `SelfieNode`
pattern: a tiny `@Observable` node persisting its answer and emitting a
`NodeBrainSlice`. One generic `PromptNode` keyed by entry ID covers all three —
no hand-written manager per prompt. Photo prompts reuse `SelfieVisionReader` for
the on-device content read; the slice is `answer + vision classifications/OCR`.

## Data model

```swift
enum NodeCaptureKind: String, Codable {
    case source, photo, text, choice
}

struct NodeCatalogEntry: Identifiable, Codable {
    let id: String              // "apple-music", "fit-photo", "latest-book"
    let title: String           // "photo of your fit"
    let subtitle: String        // "so I can see how you dress"
    let captureKind: NodeCaptureKind
    let sourceRoute: NodeRoute? // set only for .source entries
    let prompt: PromptSpec?     // set for photo/text/choice; options, placeholder, char limit
    let glyph: String           // SF Symbol for the morsel
    let brainNodeID: BrainNodeID
}

struct StepReward: Codable {
    var growth = true           // always; kept for symmetry
    var insight = true
    var cosmetic: CosmeticID?   // nil = none
    var recommendation = false  // dormant until discovery engine exists
}

struct ScheduleStep: Codable {
    let entryID: String              // -> NodeCatalogEntry.id
    let reward: StepReward
    var intervalHours: Double = 24   // authored per step; dev panel scales globally
}

struct ProgressionState: Codable {
    var cursor = 0                    // index into schedule
    var nextUnlockAt: Date?           // nil = an unlock is available NOW
    var completedEntryIDs: [String] = []
    var pendingUnlockEntryID: String? // unlocked, not yet fed/consumed
    var mode: Mode = .drip            // .drip -> .cooldown when schedule exhausted
    var earnedCosmetics: [CosmeticID] = []
    var activeCosmetic: CosmeticID?
    enum Mode: String, Codable { case drip, cooldown }
}
```

**Owner:** a new `@Observable NodeProgression` manager, injected in `WormApp`
alongside the nodes, persisting `ProgressionState` through `SnapshotStore`. It is
the single brain of time. Exposes:

- `availableUnlock: NodeCatalogEntry?`
- `timeRemaining: TimeInterval?`
- `arm()` — set `nextUnlockAt = now + interval`, schedule the notification
- `claim(entry:)` — mark fed/consumed, apply rewards
- `advance()` — move the cursor, re-arm (or flip to cooldown)

Views only read/observe it.

## Timer system

No background loop — one persisted `Date` (`nextUnlockAt`), everything derived:

- **Availability** is a pure comparison: `nextUnlockAt == nil || now >= nextUnlockAt`.
  Checked on app foreground (`scenePhase`) and on home appear, so an unlock that
  matured while the app was closed is simply *there* on return.
- **Visible countdown** uses `TimelineView(.periodic:)` ticking once/second,
  reading `timeRemaining`. UI-only; no `Timer`, no polling, no battery cost.
- **Arming** sets the date + schedules the notification. Called after a node is
  fed/claimed.

## Notification system

Local, not remote. Everything is on-device and the fire time is known at arm
time, so `UNUserNotificationCenter` local notifications are correct and
backend-free.

- On `arm()`, schedule one trigger for `nextUnlockAt` with a stable identifier
  (`"worm.unlock"`). Re-arming cancels the old one first — never stack duplicates.
- **Permission asked contextually**, never at launch: first time we arm a
  countdown (right after the FTUE first-insight delight), with a one-line in-app
  primer before the system sheet. If denied, the countdown still works in-app; we
  just don't nudge.
- Copy comes from the *next* catalog entry: *"Your worm's hungry. Show it your
  bookshelf."* Tapping deep-links to home with the unlock ready.
- A `UNUserNotificationCenterDelegate` on the app handles foreground presentation
  and tap routing.

## Home UI

Reuses the onboarding grammar (ink morsel → hover → tap to feed → gulp → grow →
caption). Nothing new to learn.

**Countdown header** — slides down from offscreen top on home appear. One capsule
pinned top-center, paper/ink + SF Rounded:

- **Locked:** slim pill — worm glyph + `"next node in 4h 12m"` + thin depleting
  track. The "check back in a while" beat. Ticks via `TimelineView`.
- **Available:** fills to ink, subtle pulse/haptic, `"a new node unlocked"`.
  Tapping drops the unlocked morsel into the existing hover spot.

**Unlock → feed → reward sequence** (one choreographed run):

1. Morsel drifts to `hoverPoint` with the entry's glyph + title. "tap to feed"
   hint after a beat.
2. Tap → `.source` runs the real connect/sync; `.photo/.text/.choice` presents a
   lightweight capture sheet (camera / one text field / choice chips) *before*
   the gulp. The answer becomes the morsel.
3. Gulp + grow (existing `HomeWorm` gulp grammar) + `digestCaption`.
4. **Reward reveal**, gated by `StepReward`: `.insight` → fresh observed line in
   `FirstInsightReveal` style; `.cosmetic` → worm visibly re-skins with an
   "unlocked: <name>" tag.
5. `advance()` → arms the next countdown → header slides back to locked.

**Always-open "connect more"** — the profile surface gets a quiet "feed me more"
affordance; always-available source morsels (e.g. Apple Music) still float on
home, ungated. Eager users connect anytime; no scheduled reward.

**Cosmetics** apply by mapping `activeCosmetic` → the `Worm`'s `color`/`eyeColor`
(and later app accent). Small, real, already supported by the mascot.

## Authored first-run schedule

Onboarding already did selfie + Spotify; this picks up day 1.

| Day | Entry | Kind | Reward |
|---|---|---|---|
| 1 | Apple Music | source | growth + insight |
| 2 | "photo of your fit" | photo | growth + insight + cosmetic (worm color) |
| 3 | "latest book you read" | text | growth only |
| 4 | YouTube | source | growth + insight |
| 5 | "what'd you get up to this weekend" | text | growth + insight |
| 6 | "go-to comfort movie" | choice/text | growth + cosmetic (eye/accent) |
| 7 | Photos | source | growth + insight |
| 8 | "snap your bookshelf" | photo | growth + insight + cosmetic |
| 9 | Contacts | source | growth + insight |
| 10 | Calendar | source | growth + insight |

After the last scripted step → **cooldown mode**: offers remaining catalog
entries and a rotating bank of extra light prompts ("a song stuck in your head",
"last concert", "your desk right now") on the repeating timer, so it never
dead-ends.

## Dev panel (Profile → Brain, behind `DevFlags`)

- Interval scale slider (24h → seconds)
- "Unlock now" / "Advance step" / "Reset progression"
- "Fire test notification"
- "Jump to cooldown mode"
- Live readout: `cursor / nextUnlockAt / pendingUnlock / mode / earnedCosmetics`
- Cosmetic picker (apply any cosmetic to preview)

## Files (planned)

New:
- `Worm/Progression/NodeCatalog.swift` — static catalog + authored schedule
- `Worm/Progression/NodeProgression.swift` — `@Observable` owner + state
- `Worm/Progression/ProgressionModels.swift` — `NodeCatalogEntry`, `StepReward`,
  `ScheduleStep`, `ProgressionState`, `CosmeticID`, `PromptSpec`
- `Worm/Progression/UnlockNotifications.swift` — `UNUserNotificationCenter` wrapper
- `Worm/Nodes/Prompt/PromptNode.swift` — generic `@Observable` prompt node
- `Worm/Nodes/Prompt/PromptCaptureView.swift` — camera / text / choice sheet
- `Worm/App/CountdownHeaderView.swift` — the sliding header

Modified:
- `Worm/App/WormApp.swift` — inject `NodeProgression`, set notification delegate
- `Worm/App/WormHomeView.swift` — header, unlock-driven morsel, reward reveal
- `Worm/App/RootView.swift` — deep-link routing from notification tap
- `Worm/Profile/ProfileView.swift` — dev panel + "connect more"
- `Worm/Mascot/Worm.swift` — apply cosmetic color/eye
- `Worm/App/DevFlags.swift` — progression dev flag
- `Worm/Profile/TasteProfile.swift` / brain slice wiring — prompt-node slices
- `docs/vision.md` §8 — add the progression loop to the roadmap
- `docs/node-progression.md` — reference doc for the catalog + authoring

## Non-goals / dormant

- The music **recommendation** reward is wired in the schema but never fires
  until the discovery engine exists; it's on its own later timer system.
- No backend / remote push. Everything on-device.
- No monetization ("skip the wait") in v1 — the soft-gate hook is out of scope.
</content>
</invoke>
