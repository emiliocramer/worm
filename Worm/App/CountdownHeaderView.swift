import SwiftUI

/// The countdown header pinned at the top of home. Not a toast: a big stacked
/// title. Two states, both the same shape (an eyebrow word, the "worm food:"
/// title, then a value line):
///   • locked: eyebrow "next", value is the clock ticking down to the next node
///   • available: eyebrow "new", value "ready", tap to open
/// It reads `NodeProgression` directly (it's @Observable, so reading
/// `timeRemaining` / `availableUnlock` in the body tracks correctly) and slides
/// down from offscreen-top on appear. No feed logic lives here.
struct CountdownHeaderView: View {
    let progression: NodeProgression
    let ink: Color
    let paper: Color
    var onOpen: () -> Void

    @State private var entered = false
    @State private var pulsing = false
    @State private var lastAvailableID: String?

    var body: some View {
        // Drive the WHOLE view off a 1-second tick so the outer locked ->
        // available branch re-evaluates as wall-clock time passes (both
        // `availableUnlock` and `timeRemaining` read a non-observable clock).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let available = progression.availableUnlock
            let remaining = progression.timeRemaining

            Group {
                if available != nil {
                    availableTitle
                } else if remaining != nil {
                    lockedTitle(remaining: remaining ?? 0)
                }
            }
            .offset(y: entered ? 0 : -80)
            .opacity(entered ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
                    entered = true
                }
                if available != nil {
                    lastAvailableID = available?.id
                    startPulse()
                }
            }
            .onChange(of: available?.id) { _, newValue in
                // Fire the haptic once, the tick it first becomes available.
                if newValue != nil, newValue != lastAvailableID {
                    Haptics.impact(.medium)
                    startPulse()
                } else if newValue == nil {
                    pulsing = false
                }
                lastAvailableID = newValue
            }
        }
    }

    // MARK: - Locked (counting down)

    private func lockedTitle(remaining: TimeInterval) -> some View {
        titleStack(eyebrow: "next", value: Self.clock(remaining), valueMonospaced: true)
    }

    // MARK: - Available (unlocked, tap to open)

    private var availableTitle: some View {
        Button(action: onOpen) {
            titleStack(eyebrow: "new", value: "ready", valueMonospaced: false)
        }
        .buttonStyle(.plain)
        .scaleEffect(pulsing ? 1.035 : 1.0)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulsing)
        .accessibilityLabel("new worm food, ready")
    }

    // MARK: - Shared stacked title

    /// eyebrow word, the "worm food:" title, then the value (clock or "ready").
    /// Serif for the words, monospaced for the clock. No background, no icon.
    private func titleStack(eyebrow: String, value: String, valueMonospaced: Bool) -> some View {
        VStack(spacing: 2) {
            Text(eyebrow)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(ink.opacity(0.4))
            Text("worm food:")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(ink.opacity(0.85))
            Text(value)
                .font(.system(size: 40, weight: .heavy, design: valueMonospaced ? .monospaced : .serif))
                .foregroundStyle(ink.opacity(0.92))
                .monospacedDigit()
        }
        .multilineTextAlignment(.center)
    }

    private func startPulse() {
        // Kick the repeatForever animation on the next runloop so the initial
        // state is registered before it starts oscillating.
        DispatchQueue.main.async { pulsing = true }
    }

    /// Clock countdown: "05:43" under an hour, "1:05:43" once there are hours.
    private static func clock(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
