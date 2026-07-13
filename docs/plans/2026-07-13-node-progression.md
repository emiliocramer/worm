# Node Progression Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the engagement loop that makes users crave building out their graph — a curated daily drip of unlockable brain nodes (source + prompt kinds), each granting configurable rewards, gated by a countdown header and local notifications, falling back to a perpetual cooldown.

**Architecture:** A single `@Observable NodeProgression` manager owns *time* (a persisted `nextUnlockAt` date + a cursor into an authored schedule). Pure state-machine logic (arm / advance / availability / drip→cooldown) is TDD'd in `WormTests/`. The home UI reuses the existing morsel-eat/gulp grammar; a sliding countdown header reads the progression. Prompt nodes (`.photo/.text/.choice`) mirror the `SelfieNode` pattern via one generic `PromptNode`. Local `UNUserNotificationCenter` notifications are armed at unlock time — no backend.

**Tech Stack:** Swift 5.9+, SwiftUI, `@Observable` (Observation), XCTest, `UserNotifications`, XcodeGen. Design doc: `docs/plans/2026-07-13-node-progression-design.md`.

**Conventions:** Match surrounding idiom (paper `#F7F5ED` / black ink, SF Rounded, `SnapshotStore` persistence, node lifecycle). No em-dashes in any user-facing copy (deterministic audit exists). After adding/removing files, `xcodegen generate` before building.

**Build / test commands:**
```sh
xcodegen generate
# Unit tests (the TDD loop for logic tasks):
xcodebuild -project Worm.xcodeproj -scheme Worm \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug test CODE_SIGNING_ALLOWED=NO
# Build only (verify UI tasks compile):
xcodebuild -project Worm.xcodeproj -scheme Worm \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

> **Note on TDD here:** the progression state machine, catalog/schedule integrity, and reward logic are pure and MUST be TDD'd (Tasks 1–4). UI/animation/notification-scheduling tasks (Tasks 5–10) are not unit-testable; each ends with a build + a manual verification checklist driven through the dev panel.

---

## Task 1: Progression models

**Files:**
- Create: `Worm/Progression/ProgressionModels.swift`
- Test: `WormTests/ProgressionTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import Worm

final class ProgressionTests: XCTestCase {
    func test_stepReward_defaults_growthAndInsightOn_recommendationDormant() {
        let r = StepReward()
        XCTAssertTrue(r.growth)
        XCTAssertTrue(r.insight)
        XCTAssertNil(r.cosmetic)
        XCTAssertFalse(r.recommendation)
    }

    func test_progressionState_roundTripsThroughJSON() throws {
        var state = ProgressionState()
        state.cursor = 3
        state.mode = .cooldown
        state.completedEntryIDs = ["apple-music", "fit-photo"]
        state.earnedCosmetics = [.midnight]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ProgressionState.self, from: data)
        XCTAssertEqual(decoded.cursor, 3)
        XCTAssertEqual(decoded.mode, .cooldown)
        XCTAssertEqual(decoded.completedEntryIDs, ["apple-music", "fit-photo"])
        XCTAssertEqual(decoded.earnedCosmetics, [.midnight])
    }
}
```

**Step 2: Run test to verify it fails** — Expected: compile failure ("cannot find 'StepReward'").

**Step 3: Write minimal implementation**

```swift
import Foundation

enum NodeCaptureKind: String, Codable, Hashable {
    case source, photo, text, choice
}

/// A short self-report prompt (photo caption / text / choice). Nil for `.source`.
struct PromptSpec: Codable, Hashable {
    var placeholder: String? = nil        // text
    var options: [String]? = nil          // choice
    var allowsFreeText: Bool = false      // choice + "other"
    var charLimit: Int = 120
}

/// Cosmetic reward identifiers. Small, hand-authored; maps to worm color/eye.
enum CosmeticID: String, Codable, Hashable, CaseIterable {
    case midnight      // deep blue-black worm
    case clay          // warm terracotta
    case moss          // muted green
    case paperInverse  // paper-colored worm, ink eyes
}

struct StepReward: Codable, Hashable {
    var growth = true
    var insight = true
    var cosmetic: CosmeticID? = nil
    var recommendation = false   // dormant until the discovery engine exists
}

struct ScheduleStep: Codable, Hashable {
    let entryID: String
    var reward = StepReward()
    var intervalHours: Double = 24
}

struct ProgressionState: Codable, Hashable {
    enum Mode: String, Codable { case drip, cooldown }
    var cursor = 0
    var nextUnlockAt: Date? = nil
    var completedEntryIDs: [String] = []
    var pendingUnlockEntryID: String? = nil
    var mode: Mode = .drip
    var earnedCosmetics: [CosmeticID] = []
    var activeCosmetic: CosmeticID? = nil
}
```

**Step 4: Run tests** — Expected: PASS.

**Step 5: Commit**

```bash
xcodegen generate
git add Worm/Progression/ProgressionModels.swift WormTests/ProgressionTests.swift Worm.xcodeproj
git commit -m "feat(progression): models for schedule, reward, and state"
```

---

## Task 2: Node catalog + authored schedule

**Files:**
- Create: `Worm/Progression/NodeCatalog.swift`
- Test: `WormTests/ProgressionTests.swift` (append)

**Step 1: Write the failing tests**

```swift
func test_everyScheduleStep_referencesARealCatalogEntry() {
    let ids = Set(NodeCatalog.all.map(\.id))
    for step in NodeCatalog.firstRunSchedule {
        XCTAssertTrue(ids.contains(step.entryID), "schedule step \(step.entryID) has no catalog entry")
    }
}

func test_catalogEntryIDs_areUnique() {
    let ids = NodeCatalog.all.map(\.id)
    XCTAssertEqual(ids.count, Set(ids).count)
}

func test_sourceEntries_haveRoute_promptEntries_haveSpec() {
    for e in NodeCatalog.all {
        switch e.captureKind {
        case .source:
            XCTAssertNotNil(e.sourceRoute, "\(e.id) is .source but has no route")
        case .photo, .text, .choice:
            XCTAssertNotNil(e.prompt, "\(e.id) is a prompt kind but has no PromptSpec")
        }
    }
}

func test_cooldownPool_excludesScheduledSourceNodes() {
    // Cooldown should not re-offer the curated schedule's source nodes.
    let scheduled = Set(NodeCatalog.firstRunSchedule.map(\.entryID))
    for e in NodeCatalog.cooldownPool {
        XCTAssertFalse(scheduled.contains(e.id) && e.captureKind == .source)
    }
}
```

**Step 2: Run to verify failure** — Expected: "cannot find 'NodeCatalog'".

**Step 3: Implement** — `NodeCatalogEntry` + the static catalog + schedule + cooldown pool. Full authored content (matches the design table; keep copy em-dash-free, lowercase-casual to match onboarding voice):

```swift
import Foundation

struct NodeCatalogEntry: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let captureKind: NodeCaptureKind
    let sourceRoute: NodeRoute?
    let prompt: PromptSpec?
    let glyph: String
    let brainNodeID: BrainNodeID   // .prompts for all prompt entries (see Task 8)
}

enum NodeCatalog {
    static let all: [NodeCatalogEntry] = source + prompts

    static let source: [NodeCatalogEntry] = [
        .init(id: "apple-music", title: "your other music", subtitle: "connect Apple Music so I hear the rest",
              captureKind: .source, sourceRoute: .appleMusic, prompt: nil, glyph: "music.note", brainNodeID: .appleMusic),
        .init(id: "youtube", title: "what you watch", subtitle: "connect YouTube so I see past the music",
              captureKind: .source, sourceRoute: .youtube, prompt: nil, glyph: "play.rectangle.fill", brainNodeID: .youtube),
        .init(id: "photos", title: "your camera roll", subtitle: "let me see what you point a camera at",
              captureKind: .source, sourceRoute: .photos, prompt: nil, glyph: "photo.on.rectangle", brainNodeID: .photos),
        .init(id: "contacts", title: "your people", subtitle: "who you keep close says a lot",
              captureKind: .source, sourceRoute: .contacts, prompt: nil, glyph: "person.2.fill", brainNodeID: .contacts),
        .init(id: "calendar", title: "how you spend time", subtitle: "connect your calendar",
              captureKind: .source, sourceRoute: .calendar, prompt: nil, glyph: "calendar", brainNodeID: .calendar),
    ]

    static let prompts: [NodeCatalogEntry] = [
        .init(id: "fit-photo", title: "photo of your fit", subtitle: "so I can see how you dress",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "camera.fill", brainNodeID: .prompts),
        .init(id: "latest-book", title: "the last book you read", subtitle: "title's enough",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "title, author, whatever you remember"), glyph: "book.fill", brainNodeID: .prompts),
        .init(id: "weekend", title: "what'd you get up to this weekend", subtitle: "a sentence is plenty",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "one line"), glyph: "sun.max.fill", brainNodeID: .prompts),
        .init(id: "comfort-movie", title: "your comfort movie", subtitle: "the one you rewatch",
              captureKind: .choice, sourceRoute: nil,
              prompt: PromptSpec(options: ["rom-com", "action", "A24 sad", "horror", "animation", "a documentary"], allowsFreeText: true),
              glyph: "film.fill", brainNodeID: .prompts),
        .init(id: "bookshelf", title: "snap your bookshelf", subtitle: "or whatever's on the shelf",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "books.vertical.fill", brainNodeID: .prompts),
        // extra cooldown-only prompts
        .init(id: "stuck-song", title: "a song stuck in your head", subtitle: "right now",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "song + artist"), glyph: "music.quarternote.3", brainNodeID: .prompts),
        .init(id: "last-concert", title: "the last show you went to", subtitle: "live music, comedy, anything",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "who, and roughly when"), glyph: "ticket.fill", brainNodeID: .prompts),
        .init(id: "desk-now", title: "your desk right now", subtitle: "no cleaning up first",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "camera.viewfinder", brainNodeID: .prompts),
    ]

    /// The curated first-run drip (design §"Authored first-run schedule").
    static let firstRunSchedule: [ScheduleStep] = [
        ScheduleStep(entryID: "apple-music",  reward: StepReward(insight: true)),
        ScheduleStep(entryID: "fit-photo",    reward: StepReward(insight: true, cosmetic: .midnight)),
        ScheduleStep(entryID: "latest-book",  reward: StepReward(insight: false)),   // "day 3 no insight"
        ScheduleStep(entryID: "youtube",      reward: StepReward(insight: true)),
        ScheduleStep(entryID: "weekend",      reward: StepReward(insight: true)),
        ScheduleStep(entryID: "comfort-movie", reward: StepReward(insight: false, cosmetic: .clay)),
        ScheduleStep(entryID: "photos",       reward: StepReward(insight: true)),
        ScheduleStep(entryID: "bookshelf",    reward: StepReward(insight: true, cosmetic: .moss)),
        ScheduleStep(entryID: "contacts",     reward: StepReward(insight: true)),
        ScheduleStep(entryID: "calendar",     reward: StepReward(insight: true)),
    ]

    /// After the schedule is exhausted, cooldown offers whatever's left, prompts first.
    static let cooldownPool: [NodeCatalogEntry] =
        prompts.filter { !firstRunSchedule.map(\.entryID).contains($0.id) }

    static func entry(_ id: String) -> NodeCatalogEntry? { all.first { $0.id == id } }
}
```

> Add `.prompts` to `BrainNodeID` in Task 8 first if compiling standalone; for this task, temporarily use `.selfie` and switch in Task 8, OR do Task 8's one-line enum add now. Recommended: make the `BrainNodeID.prompts` enum addition the very first step of Task 8 and land Task 8 immediately after this task.

**Step 4: Run tests** — Expected: PASS (after `.prompts` exists).

**Step 5: Commit**

```bash
git add Worm/Progression/NodeCatalog.swift WormTests/ProgressionTests.swift Worm.xcodeproj
git commit -m "feat(progression): authored node catalog + first-run schedule"
```

---

## Task 3: NodeProgression state machine — availability & arming

**Files:**
- Create: `Worm/Progression/NodeProgression.swift`
- Test: `WormTests/ProgressionTests.swift` (append)

Design the manager so its clock is **injectable** for tests: a `now: () -> Date` closure (defaults to `Date.init`) and an injectable `SnapshotStore` filename. Notifications are behind a protocol (Task 6) so tests pass a no-op.

**Step 1: Write the failing tests**

```swift
@MainActor
func test_freshProgression_firstUnlockAvailableImmediately() {
    let p = NodeProgression(scheduler: NoopUnlockScheduler(), storeFilename: "test-\(UUID().uuidString).json")
    XCTAssertNotNil(p.availableUnlock)
    XCTAssertEqual(p.availableUnlock?.id, "apple-music")
    XCTAssertNil(p.timeRemaining)
}

@MainActor
func test_arm_setsFutureDate_andHidesAvailability() {
    var clock = Date(timeIntervalSince1970: 1_000_000)
    let p = NodeProgression(scheduler: NoopUnlockScheduler(),
                            storeFilename: "test-\(UUID().uuidString).json",
                            now: { clock })
    p.arm(hours: 24)
    XCTAssertNil(p.availableUnlock)
    XCTAssertEqual(p.timeRemaining ?? 0, 24 * 3600, accuracy: 1)
    clock = clock.addingTimeInterval(24 * 3600 + 1)   // time passes
    XCTAssertNotNil(p.availableUnlock)
    XCTAssertNil(p.timeRemaining)
}
```

**Step 2: Run to verify failure.**

**Step 3: Implement (availability + arm only for now)**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class NodeProgression {
    private(set) var state: ProgressionState

    @ObservationIgnored private let scheduler: UnlockScheduling
    @ObservationIgnored private let store: SnapshotStore<ProgressionState>
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var schedule: [ScheduleStep] { NodeCatalog.firstRunSchedule }

    init(scheduler: UnlockScheduling,
         storeFilename: String = "node-progression.json",
         now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.store = SnapshotStore(filename: storeFilename)
        self.now = now
        self.state = store.load() ?? ProgressionState()
    }

    // The entry the user could unlock right now, if the gate is open.
    var availableUnlock: NodeCatalogEntry? {
        guard isUnlockReady else { return nil }
        return nextEntry
    }

    var timeRemaining: TimeInterval? {
        guard let at = state.nextUnlockAt else { return nil }
        let remaining = at.timeIntervalSince(now())
        return remaining > 0 ? remaining : nil
    }

    private var isUnlockReady: Bool {
        guard nextEntry != nil else { return false }
        guard let at = state.nextUnlockAt else { return true }  // nil = ready now
        return now() >= at
    }

    /// The next entry to offer: schedule cursor in drip mode, pool in cooldown.
    private var nextEntry: NodeCatalogEntry? {
        switch state.mode {
        case .drip:
            guard state.cursor < schedule.count else { return nil }
            return NodeCatalog.entry(schedule[state.cursor].entryID)
        case .cooldown:
            return NodeCatalog.cooldownPool.first { !state.completedEntryIDs.contains($0.id) }
        }
    }

    func arm(hours: Double) {
        state.nextUnlockAt = now().addingTimeInterval(hours * 3600)
        persist()
        // notification scheduling wired in Task 6
    }

    private func persist() { store.save(state) }
}
```

Add a test double in the test file:

```swift
final class NoopUnlockScheduler: UnlockScheduling {
    func schedule(at date: Date, title: String, body: String) {}
    func cancel() {}
    func requestAuthorizationIfNeeded() async {}
}
```

And the protocol stub (move to Task 6's file later, define here to compile):

```swift
protocol UnlockScheduling {
    func schedule(at date: Date, title: String, body: String)
    func cancel()
    func requestAuthorizationIfNeeded() async
}
```

**Step 4: Run tests** — Expected: PASS.

**Step 5: Commit**

```bash
git add Worm/Progression/NodeProgression.swift WormTests/ProgressionTests.swift Worm.xcodeproj
git commit -m "feat(progression): availability + arm state machine (TDD)"
```

---

## Task 4: NodeProgression — claim, advance, drip→cooldown

**Files:**
- Modify: `Worm/Progression/NodeProgression.swift`
- Test: `WormTests/ProgressionTests.swift` (append)

**Step 1: Write the failing tests**

```swift
@MainActor
func test_claimThenAdvance_movesCursor_recordsCompletion_armsNext() {
    var clock = Date(timeIntervalSince1970: 2_000_000)
    let p = NodeProgression(scheduler: NoopUnlockScheduler(),
                            storeFilename: "test-\(UUID().uuidString).json", now: { clock })
    let first = p.availableUnlock!            // apple-music
    let reward = p.claim(entry: first)        // returns the StepReward for the reveal
    XCTAssertTrue(reward.insight)
    XCTAssertTrue(p.state.completedEntryIDs.contains("apple-music"))
    p.advance()
    XCTAssertEqual(p.state.cursor, 1)
    XCTAssertNil(p.availableUnlock)           // next is armed, not yet ready
    clock = clock.addingTimeInterval(24 * 3600 + 1)
    XCTAssertEqual(p.availableUnlock?.id, "fit-photo")
}

@MainActor
func test_advancingPastLastStep_flipsToCooldown() {
    let p = NodeProgression(scheduler: NoopUnlockScheduler(),
                            storeFilename: "test-\(UUID().uuidString).json",
                            now: { Date(timeIntervalSince1970: 0) })
    for entry in NodeCatalog.firstRunSchedule.map(\.entryID) {
        p.forceUnlockNow()
        _ = p.claim(entry: NodeCatalog.entry(entry)!)
        p.advance()
    }
    XCTAssertEqual(p.state.mode, .cooldown)
    p.forceUnlockNow()
    XCTAssertNotNil(p.availableUnlock)        // cooldown keeps offering
    XCTAssertTrue(NodeCatalog.cooldownPool.contains { $0.id == p.availableUnlock?.id })
}

@MainActor
func test_cosmeticReward_isRecordedAndActivated() {
    let p = NodeProgression(scheduler: NoopUnlockScheduler(),
                            storeFilename: "test-\(UUID().uuidString).json",
                            now: { Date(timeIntervalSince1970: 0) })
    p.forceUnlockNow(); _ = p.claim(entry: NodeCatalog.entry("apple-music")!); p.advance()
    p.forceUnlockNow(); _ = p.claim(entry: NodeCatalog.entry("fit-photo")!)  // reward has .midnight
    XCTAssertTrue(p.state.earnedCosmetics.contains(.midnight))
    XCTAssertEqual(p.state.activeCosmetic, .midnight)
}
```

**Step 2: Run to verify failure.**

**Step 3: Implement claim/advance/cooldown/dev helpers**

```swift
// Reward the user just earned; drives the reveal. Records completion + cosmetics.
@discardableResult
func claim(entry: NodeCatalogEntry) -> StepReward {
    let reward = currentReward(for: entry)
    if !state.completedEntryIDs.contains(entry.id) {
        state.completedEntryIDs.append(entry.id)
    }
    if let cosmetic = reward.cosmetic {
        if !state.earnedCosmetics.contains(cosmetic) { state.earnedCosmetics.append(cosmetic) }
        state.activeCosmetic = cosmetic
    }
    state.pendingUnlockEntryID = nil
    persist()
    return reward
}

func advance() {
    switch state.mode {
    case .drip:
        state.cursor += 1
        if state.cursor >= schedule.count { state.mode = .cooldown }
        arm(hours: currentInterval)
    case .cooldown:
        arm(hours: cooldownIntervalHours)
    }
}

private func currentReward(for entry: NodeCatalogEntry) -> StepReward {
    if state.mode == .drip, state.cursor < schedule.count,
       schedule[state.cursor].entryID == entry.id {
        return schedule[state.cursor].reward
    }
    return StepReward(insight: true, cosmetic: nil)   // cooldown default
}

private var currentInterval: Double {
    guard state.mode == .drip, state.cursor < schedule.count else { return cooldownIntervalHours }
    return schedule[state.cursor].intervalHours
}

var cooldownIntervalHours: Double = 24   // var so the dev panel can scale it

// MARK: - Dev / test helpers
func forceUnlockNow() { state.nextUnlockAt = nil; scheduler.cancel(); persist() }
func reset() { state = ProgressionState(); scheduler.cancel(); persist() }
func jumpToCooldown() { state.mode = .cooldown; state.cursor = schedule.count; persist() }
```

**Step 4: Run tests** — Expected: PASS.

**Step 5: Commit**

```bash
git add Worm/Progression/NodeProgression.swift WormTests/ProgressionTests.swift
git commit -m "feat(progression): claim/advance + drip->cooldown transition (TDD)"
```

---

## Task 5: BrainNodeID.prompts + generic PromptNode + slice

**Files:**
- Modify: `Worm/Profile/BrainModels.swift` (add `case prompts` to `BrainNodeID`)
- Create: `Worm/Nodes/Prompt/PromptNode.swift`
- Create: `Worm/Nodes/Prompt/PromptStore.swift` (or reuse `SnapshotStore` directly)
- Test: `WormTests/ProgressionTests.swift` (append a slice test)

**Step 1: Add the enum case.** In `BrainModels.swift`, add `case prompts` after `case selfie`. Grep for exhaustive `switch` over `BrainNodeID` (display names, intents) and add the `.prompts` arm ("Self prompts" / intent tags: self-report, aesthetics, culture). Build to find every non-exhaustive switch.

**Step 2: Write the failing test**

```swift
@MainActor
func test_promptNode_persistsAnswers_andEmitsSlice() {
    let node = PromptNode(storeFilename: "test-\(UUID().uuidString).json")
    node.record(entryID: "latest-book", title: "the last book you read", answer: "Piranesi, Susanna Clarke")
    let slice = node.brainSlice()
    XCTAssertNotNil(slice)
    XCTAssertEqual(slice?.nodeID, .prompts)
    XCTAssertTrue(slice!.evidence.contains { $0.contains("Piranesi") })
}
```

**Step 3: Implement `PromptNode`.** One `@Observable` node holding `[PromptAnswer]` (entryID, title, text, optional photo-vision keywords, date), persisted via `SnapshotStore`. `record(entryID:title:answer:)` and `recordPhoto(entryID:title:visionKeywords:)`. `brainSlice()` reduces all answers into one `NodeBrainSlice(nodeID: .prompts, ...)` with summary, facts (one per answer), evidence strings, retrieval chunks, freshness=most-recent, confidence per count. Mirror the `NodeBrainSlice` shape used by `SelfieNode`/`BrainSliceBuilder` (read `Worm/Profile/BrainSliceBuilder.swift` for the exact initializer + fields before writing).

**Step 4: Run tests** — Expected: PASS.

**Step 5: Commit**

```bash
xcodegen generate
git add Worm/Profile/BrainModels.swift Worm/Nodes/Prompt Worm.xcodeproj WormTests/ProgressionTests.swift
git commit -m "feat(progression): prompts brain node + generic PromptNode (TDD)"
```

---

## Task 6: Local notification scheduler

**Files:**
- Create: `Worm/Progression/UnlockNotifications.swift`
- Modify: `Worm/Progression/NodeProgression.swift` (call scheduler in `arm`/`cancel`)

**Step 1:** Move the `UnlockScheduling` protocol here. Implement `UnlockNotificationScheduler: UnlockScheduling` over `UNUserNotificationCenter`:
- `requestAuthorizationIfNeeded()` — check `notificationSettings().authorizationStatus`; request `[.alert, .sound]` only if `.notDetermined`.
- `schedule(at:title:body:)` — remove pending `"worm.unlock"`, then add a `UNNotificationRequest` with a `UNCalendarNotificationTrigger` (or `UNTimeIntervalNotificationTrigger` for sub-minute dev intervals) and `userInfo: ["route": "unlock"]`.
- `cancel()` — `removePendingNotificationRequests(withIdentifiers: ["worm.unlock"])`.

**Step 2:** Wire into `NodeProgression.arm(hours:)`: after setting the date, call `scheduler.schedule(at: nextUnlockAt!, title:body:)` using copy from the *next* entry (`"\(name) is hungry."` / `"Show it your \(entry.title)."` — em-dash-free). `forceUnlockNow`/`reset` call `scheduler.cancel()`.

**Step 3:** No unit test (system API). Build only.

**Step 4: Verify** — build succeeds:
```sh
xcodegen generate && xcodebuild -project Worm.xcodeproj -scheme Worm -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

**Step 5: Commit**

```bash
git add Worm/Progression Worm.xcodeproj && git commit -m "feat(progression): local unlock notification scheduler"
```

---

## Task 7: Inject progression + notification delegate in WormApp

**Files:**
- Modify: `Worm/App/WormApp.swift`
- Modify: `Worm/App/RootView.swift` (deep-link on notification tap)

**Step 1:** Add `@State private var progression = NodeProgression(scheduler: UnlockNotificationScheduler())` and `@State private var promptNode = PromptNode()`. Inject both via `.environment(...)`. In `DevFlags.constantTesting`, also `progression.reset()`.

**Step 2:** Add an `UNUserNotificationCenterDelegate` (an `NSObject` adaptor set as `UNUserNotificationCenter.current().delegate` in a `.task`). On foreground: present as banner. On tap with `userInfo["route"] == "unlock"`: publish to a lightweight `@Observable Router` (or an `@AppStorage`/`NotificationCenter` bridge) that `WormHomeView` observes to auto-open the unlock. Keep it minimal: set `progression`'s availability is already true when the timer elapsed, so the tap just needs to route to home (pop to root).

**Step 3:** Build only.

**Step 4: Verify** — build succeeds (command above).

**Step 5: Commit**

```bash
git add Worm/App/WormApp.swift Worm/App/RootView.swift && git commit -m "feat(progression): inject progression + notification delegate"
```

---

## Task 8: Countdown header

**Files:**
- Create: `Worm/App/CountdownHeaderView.swift`
- Modify: `Worm/App/WormHomeView.swift` (mount header as top overlay)

**Step 1:** Build `CountdownHeaderView` taking `NodeProgression`. Two states (paper/ink, SF Rounded, matches `WormHomeView`):
- **Locked** (`timeRemaining != nil`): slim capsule, worm glyph + `"next node in \(formatted)"` + a thin depleting progress track (fraction from the step interval). `TimelineView(.periodic(from:.now, by: 1))` for the tick.
- **Available** (`availableUnlock != nil`): capsule fills to ink, pulse + `Haptics.impact(.medium)` once, `"a new node unlocked"`, tappable → calls a `onOpen` closure.

Entrance: slides down from `-offset` on appear with `.spring`, matching the header-from-top brief. Respect safe-area top inset.

**Step 2:** In `WormHomeView`, add `@Environment(NodeProgression.self)`, mount the header as a top overlay (above the profile icon or beside it). Tapping "available" triggers the unlock morsel flow (Task 9).

**Step 3:** Build only.

**Step 4: Verify (dev panel, after Task 10):** header slides in; shows countdown when armed; flips to "unlocked" when `forceUnlockNow()` is hit.

**Step 5: Commit**

```bash
xcodegen generate && git add Worm/App/CountdownHeaderView.swift Worm/App/WormHomeView.swift Worm.xcodeproj
git commit -m "feat(progression): sliding countdown header"
```

---

## Task 9: Unlock → feed → reward flow in WormHomeView

**Files:**
- Modify: `Worm/App/WormHomeView.swift`
- Create: `Worm/Nodes/Prompt/PromptCaptureView.swift`

**Step 1: Replace the hard-coded `nextMorsel`** (currently Apple-Music-only) with the progression's `availableUnlock`. Keep the existing morsel hover/feed/gulp/grow choreography. The morsel now shows the entry's `glyph` + `title`.

**Step 2: Branch the feed by capture kind:**
- `.source` → run the existing connect/sync via the matching `@Environment` node (route through `entry.sourceRoute`), same as the current `connectAppleMusic`.
- `.photo/.text/.choice` → present `PromptCaptureView` (a `.sheet`) *before* the gulp: camera picker (photo), single `TextField` (text), or choice chips + optional free text (choice). On submit, `promptNode.record(...)` (and kick a background vision read for photos, reusing `SelfieVisionReader`), then run the gulp.

**Step 3: On successful capture:** call `let reward = progression.claim(entry:)`, run gulp+grow, then the **reward reveal**:
- `reward.insight` → synthesize/surface a fresh line (reuse `FirstInsightPipeline`/`TasteProfile`; fall back to silence if none — "silence beats a miss") in the `FirstInsightReveal` style already in `OnboardingView`.
- `reward.cosmetic` → apply via `progression.state.activeCosmetic` (Task 10 wires the worm color) + show an "unlocked: <name>" tag.
- Then `progression.advance()` → header returns to locked.

**Step 4:** Build only.

**Step 5: Commit**

```bash
xcodegen generate && git add Worm/App/WormHomeView.swift Worm/Nodes/Prompt/PromptCaptureView.swift Worm.xcodeproj
git commit -m "feat(progression): unlock->feed->reward flow on home"
```

---

## Task 10: Cosmetics on the worm + growth off completed count

**Files:**
- Modify: `Worm/Mascot/Worm.swift` (map `CosmeticID` → color/eye)
- Modify: `Worm/App/WormHomeView.swift` (`earnedSize` counts completed entries; apply `activeCosmetic`)

**Step 1:** Add `extension CosmeticID { var wormColor: Color; var eyeColor: Color }`. In `WormHomeView`, feed `HomeWorm`'s `color`/`eyeColor` from `progression.state.activeCosmetic` (default ink/paper when nil).

**Step 2:** Update `earnedSize` so every completed entry stretches him: fold `progression.state.completedEntryIDs.count` into the length term (so prompt nodes, which all share the `.prompts` brain slice and wouldn't move `populatedSliceCount`, still visibly grow him). Keep the existing per-slice/insight contribution.

**Step 3:** Build only.

**Step 4: Commit**

```bash
git add Worm/Mascot/Worm.swift Worm/App/WormHomeView.swift
git commit -m "feat(progression): worm cosmetics + growth per completed node"
```

---

## Task 11: Dev panel + "connect more"

**Files:**
- Modify: `Worm/Profile/ProfileView.swift`
- Modify: `Worm/App/DevFlags.swift` (add `static let showProgressionDevPanel = true`)

**Step 1:** In `ProfileView`, behind `DevFlags.showProgressionDevPanel`, add a "Progression (dev)" section:
- Interval scale control (sets `progression.cooldownIntervalHours` and a global dev multiplier applied in `arm`, e.g. hours→seconds).
- Buttons: "Unlock now" (`forceUnlockNow`), "Advance step" (`advance`), "Reset" (`reset`), "Jump to cooldown" (`jumpToCooldown`), "Fire test notification" (`scheduler.schedule(at: now+5s, ...)`).
- Live readout: `cursor`, `mode`, `nextUnlockAt`, `pendingUnlockEntryID`, `earnedCosmetics`, `activeCosmetic`.
- Cosmetic picker: for each `CosmeticID`, a button that sets `activeCosmetic` to preview on home.

**Step 2:** Add a shipping "connect more sources" row group (not dev-gated) listing always-available `.source` catalog entries not yet populated, each linking to its `NodeRoute`. This is the always-open ungated path.

**Step 3:** Build only.

**Step 4: Verify (the big manual pass):**
1. Reset progression in dev panel; set interval to seconds.
2. Home: header slides in, "apple-music" unlock available.
3. Feed it → gulp, grow, insight reveal, header → countdown.
4. Wait out the (seconds) timer → header flips to "unlocked"; next is "fit-photo".
5. Feed photo prompt → capture sheet → gulp → cosmetic reveal → worm re-skins.
6. Advance through to step 10 → mode flips to cooldown → still offers prompts.
7. Kill app during a countdown, relaunch → unlock matured shows immediately.
8. Grant notifications; arm; background app; confirm the local notification fires and tapping opens home.

**Step 5: Commit**

```bash
git add Worm/Profile/ProfileView.swift Worm/App/DevFlags.swift
git commit -m "feat(progression): dev panel + always-open connect-more"
```

---

## Task 12: Documentation

**Files:**
- Create: `docs/node-progression.md`
- Modify: `docs/vision.md` (§8 roadmap: add the progression loop under "Now (built)")
- Modify: `README.md` (one line pointing at the progression system)

**Step 1:** Write `docs/node-progression.md`: the catalog + how to author a schedule step, capture kinds, reward types (incl. dormant recommendation), timer/notification behavior, cosmetics, and the dev panel. Point agents at `NodeCatalog.swift` as the authoring surface.

**Step 2:** Add a short bullet to `docs/vision.md` §8 and a pointer in `README.md`.

**Step 3: Commit**

```bash
git add docs/node-progression.md docs/vision.md README.md
git commit -m "docs(progression): reference + roadmap + readme pointer"
```

---

## Definition of done

- `xcodebuild ... test` green (Tasks 1–5 logic).
- `xcodebuild ... build` green.
- Manual verification checklist in Task 11 passes on a device (notifications + camera need a real device; simulator covers the rest).
- Design doc, reference doc, vision + README updated.
- No em-dashes in any user-facing copy (the audit will drop them, but author clean).

## Deferred / dormant (do not build now)

- Recommendation reward firing (own later timer system; discovery engine first).
- Remote push / backend.
- Monetized "skip the wait".
- Per-user DB migration (existing backlog item, orthogonal).
</content>
