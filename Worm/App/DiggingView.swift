import SwiftUI

/// The "digging" home screen: the worm is off combing the internet for music,
/// and the screen *is* that combing. A tall stack of paper sheet-edges fills the
/// screen; a finger runs down its length, bending each sheet open to reveal a
/// sliver of color from between them. When it reaches the bottom, the whole
/// screenful of paper heaves up to fresh pages and the comb starts again — comb
/// down, advance, comb down — an endless sift through everything out there.
///
/// First version: the slivers are just colors. Later they become real content.
struct DiggingView: View {
    var allowsHaptics = true

    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    private let sheet = Color(red: 0.62, green: 0.61, blue: 0.59)

    // Deep, inky, print-shop glimpses — stand-ins for content/artwork from across
    // the web. Richer and more analog than a default mid-saturation rainbow.
    private let palette: [Color] = [
        Color(red: 0.55, green: 0.17, blue: 0.15),  // oxblood
        Color(red: 0.15, green: 0.21, blue: 0.34),  // ink navy
        Color(red: 0.74, green: 0.49, blue: 0.13),  // deep ochre
        Color(red: 0.24, green: 0.34, blue: 0.24),  // forest
        Color(red: 0.69, green: 0.32, blue: 0.16),  // burnt sienna
        Color(red: 0.37, green: 0.24, blue: 0.38),  // dusty plum
        Color(red: 0.16, green: 0.37, blue: 0.39),  // slate teal
        Color(red: 0.62, green: 0.38, blue: 0.33),  // clay
    ]

    // Layout / motion constants.
    private let spacing: CGFloat = 7        // distance between sheet edges (tight: a real stack)
    private let waveAmp: CGFloat = 3        // how much each sheet edge waves
    private let revealRadius: CGFloat = 52  // how far the crease trails above the finger
    private let bend: CGFloat = 23          // dip under the thumb
    private let combDuration: Double = 6.5  // seconds to comb one screenful, top to bottom
    private let shiftDuration: Double = 2.6 // seconds for the stack to heave up to fresh pages

    private var cycle: Double { combDuration + shiftDuration }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    draw(in: &context, size: size, time: t)
                }
            }
            .task(id: HapticsTaskKey(height: geo.size.height, allowsHaptics: allowsHaptics)) {
                await runHaptics(height: geo.size.height)
            }
        }
        .background(paper)
        .ignoresSafeArea()
    }

    /// Where the stack sits, and where the finger is, for a given time. During
    /// the comb phase the stack holds still and the finger sweeps down; during
    /// the shift phase the finger is gone and the stack scrolls up one screen.
    private func state(time: Double, height: CGFloat) -> (scrollY: CGFloat, finger: CGFloat, combing: Bool, heave: CGFloat) {
        let completed = floor(time / cycle)
        let phase = time - completed * cycle
        let base = CGFloat(completed) * height
        if phase < combDuration {
            let p = CGFloat(phase / combDuration)
            let finger = -revealRadius + p * (height + 2 * revealRadius)
            return (base, finger, true, 0)
        } else {
            let s = (phase - combDuration) / shiftDuration
            // Ease-out-back: the stack shoots up, overshoots, and settles — reads
            // as a real heave instead of a uniform drift.
            let c1 = 1.70158, c3 = c1 + 1
            let back = 1 + c3 * pow(s - 1, 3) + c1 * pow(s - 1, 2)
            let heave = sin(Double.pi * s)                      // motion intensity, peaks mid-heave
            return (base + CGFloat(back) * height, height + revealRadius * 4, false, CGFloat(heave))
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let (scrollY, finger, _, heave) = state(time: time, height: size.height)

        let fingerX = size.width * 0.5
        let sigma = size.width * 0.28
        let firstK = Int((scrollY / spacing).rounded(.down)) - 1
        let lastK = Int(((scrollY + size.height) / spacing).rounded(.down)) + 1

        for k in firstK...lastK {
            let baseY = CGFloat(k) * spacing - scrollY     // on-screen position
            let dist = baseY - finger                      // <0 above finger, >0 below
            let radius = dist <= 0 ? revealRadius : 16
            let near = max(0, 1 - abs(dist) / radius)
            let ease = near * near
            let colorIndex = ((k % palette.count) + palette.count) % palette.count
            let color = palette[colorIndex]
            let phase = Double(k) * 0.6 + time * 0.12

            var resting: [CGPoint] = []
            var edge: [CGPoint] = []
            var x: CGFloat = 0
            while x <= size.width {
                let wave = CGFloat(sin(Double(x) * 0.011 + phase)) * waveAmp
                let restY = baseY + wave
                let falloff = CGFloat(exp(-pow((x - fingerX) / sigma, 2)))
                let dipX = ease * bend * falloff
                resting.append(CGPoint(x: x, y: restY))
                edge.append(CGPoint(x: x, y: restY + dipX))
                x += 10
            }

            if ease > 0.01 {
                var fill = Path()
                fill.move(to: resting[0])
                for p in resting { fill.addLine(to: p) }
                for p in edge.reversed() { fill.addLine(to: p) }
                fill.closeSubpath()
                context.fill(fill, with: .color(color.opacity(0.45 + 0.55 * ease)))
            }

            // Persistent little content slivers, scattered through the stack —
            // fixed landmarks you can watch ride up during the heave. They sit ON
            // the sheet's edge, so the comb creases them along with everything
            // else (they're part of the stack, not floating on top of it).
            if k % 9 == 0 {
                let segWidth = size.width * 0.16
                let frac = CGFloat(((k &* 73) % 100 + 100) % 100) / 100
                let mx = frac * (size.width - segWidth)
                let segPts = edge.filter { $0.x >= mx && $0.x <= mx + segWidth }
                if segPts.count >= 2 {
                    var marker = Path()
                    for (idx, p) in segPts.enumerated() {
                        let top = CGPoint(x: p.x, y: p.y - 1.5)
                        if idx == 0 { marker.move(to: top) } else { marker.addLine(to: top) }
                    }
                    for p in segPts.reversed() { marker.addLine(to: CGPoint(x: p.x, y: p.y + 1.5)) }
                    marker.closeSubpath()
                    context.fill(marker, with: .color(color.opacity(0.30 + 0.30 * heave)))
                }
            }

            // While heaving, lay fading ghost copies below each line — a motion
            // blur that makes the upward lift read clearly.
            if heave > 0.01 {
                let smear = heave * 28
                for j in 1...3 {
                    let dy = smear * CGFloat(j) / 3
                    var ghost = Path()
                    for (idx, p) in edge.enumerated() {
                        let gp = CGPoint(x: p.x, y: p.y + dy)
                        if idx == 0 { ghost.move(to: gp) } else { ghost.addLine(to: gp) }
                    }
                    context.stroke(ghost, with: .color(sheet.opacity(0.14 * heave * (1 - CGFloat(j) / 4))), lineWidth: 1)
                }
            }

            var line = Path()
            for (idx, p) in edge.enumerated() {
                if idx == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            // Lines darken a touch during the heave so the moving stack is easier to track.
            context.stroke(line, with: .color(sheet.opacity(0.16 + 0.22 * ease + 0.18 * heave)), lineWidth: 1)
        }
    }

    /// A firm tap each time the comb crosses a sheet, plus a heavier thunk when
    /// the stack heaves up to fresh pages.
    private func runHaptics(height: CGFloat) async {
        guard allowsHaptics else { return }
        guard height > 0 else { return }
        var lastSheet = Int.min
        var lastShiftCycle = -1
        while !Task.isCancelled {
            let t = Date().timeIntervalSinceReferenceDate
            let completed = Int(floor(t / cycle))
            let (scrollY, finger, combing, _) = state(time: t, height: height)
            if combing {
                let sheetIndex = Int(((finger + scrollY) / spacing).rounded(.down))
                if sheetIndex != lastSheet {
                    lastSheet = sheetIndex
                    if finger >= 0, finger <= height {
                        Haptics.tick()
                    }
                }
            } else if completed != lastShiftCycle {
                lastShiftCycle = completed       // one thunk as the stack advances
                Haptics.impact(.medium)
            }
            try? await Task.sleep(for: .seconds(0.012))
        }
    }

    private struct HapticsTaskKey: Hashable {
        let height: CGFloat
        let allowsHaptics: Bool
    }
}

#Preview {
    DiggingView()
}
