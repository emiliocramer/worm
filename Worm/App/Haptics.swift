import UIKit

/// Tiny haptics helper. Worm should feel juiced — a fat thump when a new
/// insight lands, a warm success when the worm meets you or you commit.
@MainActor
enum Haptics {
    /// A physical impact. Default intensity is full — we want it felt.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1.0) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A reused tap for rapid-fire texture (e.g. the digging comb crossing each
    /// sheet). Reusing one prepared generator keeps fast repeats clean.
    private static let ticker: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        return generator
    }()

    static func tick(intensity: CGFloat = 0.7) {
        ticker.impactOccurred(intensity: intensity)
        ticker.prepare()
    }
}
