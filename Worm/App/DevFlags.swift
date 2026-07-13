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
    }
}
