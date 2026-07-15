import Foundation

/// Developer-only toggles. These gate in-progress or behind-the-scenes surfaces
/// that aren't part of the shipping experience yet.
enum DevFlags {
    /// Developer override for building and testing node-creation affordances even
    /// when the local device already has every node populated.
    static let DevNodeCreationAllowed = true

    /// Shows the liquid-glass "Graph" button on the home screen that opens the
    /// developer node-graph. Flip to `false` for the greeting-only home.
    static let showGraphButton = true

    /// When `true`, the app replays onboarding on every launch without clearing
    /// node snapshots or credentials. For working on the FTUE without forcing
    /// reconnects. Flip to `false` for normal app routing.
    static let constantTesting = false

    /// When `true`, home renders the full forest "world" (backdrop + foreground).
    /// When `false`, that environment is stripped and home is just the worm, its
    /// shadow, the apples, and the flow on the plain paper background.
    static let sceneEnabled = false

    /// Gates the delivery-time picker's "scene": the living sky gradient and the
    /// rising sun/moon behind the wheel. When `false`, the picker (and the notify/
    /// done steps) sit on the plain paper background with plain ink text — no
    /// time-of-day visualizer at all.
    static let deliveryTimeSceneEnabled = false

    /// Gates the daily food journey that follows the time-of-day picker: the base
    /// apples and the drip. When `false`, the first run ends at the delivery-time
    /// step (nothing feeds in yet) and home is just the worm on every launch. The
    /// whole flow stays wired behind this flag — flip to `true` to bring it back.
    static let dailyFoodJourneyEnabled = false

    /// Shows the progression control panel in Profile: live readout, unlock/advance/
    /// reset/cooldown buttons, fast-forward intervals, and a cosmetic preview picker.
    /// For testing the whole unlock loop without waiting real hours.
    static let showProgressionDevPanel = true

    /// Clears the onboarding/name flags so the first-time experience shows again.
    /// (Node snapshots/tokens are cleared via each node's `disconnect()`.)
    static func resetOnboarding() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "worm.hasCompletedOnboarding")
        defaults.removeObject(forKey: "worm.userName")
        defaults.removeObject(forKey: "worm.name")
        // The delivery-time step is part of the first run — replay it too.
        defaults.removeObject(forKey: NodeProgression.hasChosenDeliveryTimeKey)
        defaults.removeObject(forKey: NodeProgression.deliveryHourKey)
        defaults.removeObject(forKey: NodeProgression.deliveryMinuteKey)
    }
}
