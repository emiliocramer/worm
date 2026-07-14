import Foundation
import Observation

/// Schedules the local "a new node unlocked" notification. Fully implemented in
/// Task 6; the progression owns one so arming can fire it. A no-op double is used
/// in tests.
protocol UnlockScheduling {
    func schedule(at date: Date, title: String, body: String)
    func cancel()
    func requestAuthorizationIfNeeded() async
}

/// Owns the *time* of the progression: the drip cursor into the authored
/// schedule and the persisted `nextUnlockAt` clock. Availability is a pure
/// comparison against an injectable `now`, so nothing polls and tests are
/// deterministic. Claim/advance land in Task 4.
@MainActor
@Observable
final class NodeProgression {
    private(set) var state: ProgressionState

    @ObservationIgnored private let scheduler: UnlockScheduling
    @ObservationIgnored private let store: SnapshotStore<ProgressionState>
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var schedule: [ScheduleStep] { NodeCatalog.firstRunSchedule }

    var cooldownIntervalHours: Double = 24

    /// Dev-only: when set, arming uses this instead of the schedule/cooldown interval,
    /// so the countdown can be watched in seconds. nil = normal authored intervals.
    var devIntervalOverrideHours: Double? = nil

    init(scheduler: UnlockScheduling,
         storeFilename: String = "node-progression.json",
         now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.store = SnapshotStore(filename: storeFilename)
        self.now = now
        self.state = store.load() ?? .fresh
    }

    // MARK: - Base phase

    /// True while the user is still building the foundation: no countdown, a few
    /// prominent apples on home instead of the single drip morsel.
    var isBasePhase: Bool { state.mode == .base }

    /// The full base set, in authored order.
    var baseEntries: [NodeCatalogEntry] { NodeCatalog.baseEntries }

    /// Base entries the user hasn't fed yet — what home shows scattered in the trees.
    var pendingBaseEntries: [NodeCatalogEntry] {
        baseEntries.filter { !state.completedEntryIDs.contains($0.id) }
    }

    /// The entry the user could unlock right now, if the gate is open. Nil during
    /// the base phase (the base apples are offered directly, not through the drip).
    var availableUnlock: NodeCatalogEntry? {
        guard !isBasePhase, isUnlockReady else { return nil }
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
        case .base:
            return nil   // base apples are offered directly, never through the drip
        case .drip:
            guard state.cursor < schedule.count else { return nil }
            return NodeCatalog.entry(schedule[state.cursor].entryID)
        case .cooldown:
            return NodeCatalog.cooldownPool.first { !state.completedEntryIDs.contains($0.id) }
        }
    }

    /// Ask for notification permission on the real scheduler. Call once, contextually.
    func requestNotificationPermission() async {
        await scheduler.requestAuthorizationIfNeeded()
    }

    func arm(hours: Double) {
        let fireDate = now().addingTimeInterval(hours * 3600)
        state.nextUnlockAt = fireDate
        state.lastArmDurationHours = hours
        persist()
        if let entry = nextEntry {
            let (title, body) = Self.unlockCopy(for: entry)
            scheduler.schedule(at: fireDate, title: title, body: body)
        } else {
            scheduler.cancel()
        }
    }

    /// Notification copy for the upcoming unlock. Terse, worm-voiced, em-dash-free.
    /// Second person, names the thing, never a horoscope.
    private static func unlockCopy(for entry: NodeCatalogEntry) -> (String, String) {
        ("your worm's hungry", "it wants \(entry.title).")
    }

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
        case .base:
            // Only leave the base once every base apple is fed. Until then this
            // is a no-op: base feeds never arm a countdown.
            guard pendingBaseEntries.isEmpty else { return }
            state.mode = .drip
            state.cursor = 0
            arm(hours: devIntervalOverrideHours ?? currentInterval)
        case .drip:
            state.cursor += 1
            if state.cursor >= schedule.count { state.mode = .cooldown }
            arm(hours: devIntervalOverrideHours ?? currentInterval)
        case .cooldown:
            arm(hours: devIntervalOverrideHours ?? cooldownIntervalHours)
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

    // MARK: - Dev / test helpers
    func forceUnlockNow() { state.nextUnlockAt = nil; scheduler.cancel(); persist() }
    func reset() { state = .fresh; scheduler.cancel(); persist() }
    func jumpToCooldown() { state.mode = .cooldown; state.cursor = schedule.count; persist() }

    /// Dev-only: preview/apply a cosmetic directly.
    func applyCosmetic(_ id: CosmeticID?) {
        state.activeCosmetic = id
        persist()
    }

    private func persist() { store.save(state) }
}
