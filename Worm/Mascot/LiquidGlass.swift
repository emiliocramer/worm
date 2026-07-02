import SwiftUI

extension View {
    /// Applies a Liquid Glass background clipped to `shape`. Uses the system
    /// `glassEffect` on OS versions that support it, falling back to a thin
    /// material with a hairline edge everywhere else.
    @ViewBuilder
    func liquidGlass(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.25), lineWidth: 0.5))
        }
    }
}
