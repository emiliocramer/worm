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

    init(scheduler: UnlockScheduling,
         storeFilename: String = "node-progression.json",
         now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.store = SnapshotStore(filename: storeFilename)
        self.now = now
        self.state = store.load() ?? ProgressionState()
    }

    /// The entry the user could unlock right now, if the gate is open.
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

    // MARK: - Dev / test helpers
    func forceUnlockNow() { state.nextUnlockAt = nil; scheduler.cancel(); persist() }
    func reset() { state = ProgressionState(); scheduler.cancel(); persist() }
    func jumpToCooldown() { state.mode = .cooldown; state.cursor = schedule.count; persist() }

    private func persist() { store.save(state) }
}
