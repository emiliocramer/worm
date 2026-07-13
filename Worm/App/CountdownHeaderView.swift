import SwiftUI

/// The countdown header pinned at the top of home. Two states, both in the
/// paper/ink + SF Rounded aesthetic:
///   • locked: a slim glass capsule ticking down to the next node
///   • available: the capsule fills to ink and pulses, tap to open
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

    var body: some View {
        Group {
            if progression.availableUnlock != nil {
                availablePill
            } else if progression.timeRemaining != nil {
                lockedPill
            }
        }
        .offset(y: entered ? 0 : -80)
        .opacity(entered ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
                entered = true
            }
            if progression.availableUnlock != nil { startPulse() }
        }
        .onChange(of: progression.availableUnlock?.id) { _, newValue in
            if newValue != nil {
                Haptics.impact(.medium)
                startPulse()
            } else {
                pulsing = false
            }
        }
    }

    // MARK: - Locked (counting down)

    private var lockedPill: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = progression.timeRemaining ?? 0
            let window = max(1, progression.cooldownIntervalHours * 3600)
            let fraction = min(1, max(0, remaining / window))

            HStack(spacing: 7) {
                Image(systemName: "hourglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.5))
                Text("next node in \(Self.formatted(remaining))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.6))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .liquidGlass(in: Capsule())
            .overlay(alignment: .bottomLeading) {
                GeometryReader { g in
                    Capsule()
                        .fill(ink.opacity(0.22))
                        .frame(width: g.size.width * CGFloat(fraction), height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 2)
                .padding(.horizontal, 12)
                .padding(.bottom, 3)
            }
        }
    }

    // MARK: - Available (unlocked, tap to open)

    private var availablePill: some View {
        Button(action: onOpen) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(paper)
                Text("a new node unlocked")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(paper)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(ink, in: Capsule())
            .shadow(color: ink.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .scaleEffect(pulsing ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulsing)
        .accessibilityLabel("a new node unlocked")
    }

    private func startPulse() {
        // Kick the repeatForever animation on the next runloop so the initial
        // state is registered before it starts oscillating.
        DispatchQueue.main.async { pulsing = true }
    }

    /// Compact H/M/S countdown: "4h 12m", "12m 30s", or "48s" under a minute.
    private static func formatted(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
