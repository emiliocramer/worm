import SwiftUI

/// Maps an earned cosmetic to the worm's body + eye colors. Nil (no active
/// cosmetic) uses the default ink-on-paper worm; the caller supplies that.
extension CosmeticID {
    var wormColor: Color {
        switch self {
        case .midnight:     return Color(red: 0.10, green: 0.12, blue: 0.24)
        case .clay:         return Color(red: 0.70, green: 0.33, blue: 0.21)
        case .moss:         return Color(red: 0.28, green: 0.38, blue: 0.24)
        case .paperInverse: return Color(red: 0.55, green: 0.53, blue: 0.50)
        }
    }

    /// The eye color that reads against `wormColor`.
    var eyeColor: Color {
        switch self {
        case .midnight, .clay, .moss: return Color(red: 0.97, green: 0.96, blue: 0.93) // paper
        case .paperInverse:           return .black                                      // ink
        }
    }

    /// Short display name for the "unlocked" reveal.
    var displayName: String {
        switch self {
        case .midnight:     return "midnight"
        case .clay:         return "clay"
        case .moss:         return "moss"
        case .paperInverse: return "paper"
        }
    }
}
