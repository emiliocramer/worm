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

/// One authored drip step: which entry unlocks and what it rewards.
struct ScheduleStep: Codable, Hashable {
    let entryID: String
    var reward = StepReward()
    var intervalHours: Double = 24
}

/// Persisted progression: the drip cursor and the unlock clock.
struct ProgressionState: Codable, Hashable {
    /// `base` is the first-run foundation phase (a few prominent apples, no
    /// countdown); once its set is fed we flip to `drip`, then `cooldown`.
    /// The stored default is `.drip` so *decoded* legacy snapshots (which always
    /// carry a `mode` key) stay where they were; only a genuinely fresh state
    /// starts in `.base`, via `ProgressionState.fresh`.
    enum Mode: String, Codable, Hashable { case base, drip, cooldown }
    var cursor = 0
    var nextUnlockAt: Date? = nil
    var completedEntryIDs: [String] = []
    var pendingUnlockEntryID: String? = nil
    var mode: Mode = .drip
    // Array (not Set) to keep earned order stable for display.
    var earnedCosmetics: [CosmeticID] = []
    var activeCosmetic: CosmeticID? = nil
    // The duration (hours) of the most recently armed countdown, so the header
    // can size its progress track against the actual window (drip/dev intervals
    // differ from the cooldown default).
    var lastArmDurationHours: Double? = nil

    /// A brand-new install: starts in the `.base` foundation phase. Distinct
    /// from the memberwise `init()` (whose `.drip` default is what a legacy
    /// snapshot decodes to when it predates the base phase).
    static var fresh: ProgressionState {
        var state = ProgressionState()
        state.mode = .base
        return state
    }
}
