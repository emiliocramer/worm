import SwiftUI

/// THE worm. A single, reusable definition of the mascot's shape and motion —
/// configure it once, then draw it along any centerline (the splash word, a
/// loader's track, anything). Callers never re-derive how the worm looks or
/// moves; they only supply the path it should follow and, optionally, a per-
/// point mask of where it's actively inching.
struct Worm {
    var color: Color = .black
    var eyeColor: Color? = nil

    /// Belly diameter, in points. Everything else scales from this so the worm
    /// keeps its proportions at any size.
    var thickness: CGFloat = 9

    /// Hand-drawn wobble amplitude, as a multiple of `thickness`.
    var wobbleRatio: CGFloat = 0.22
    /// Inching hump height, as a multiple of `thickness`.
    var gaitHeightRatio: CGFloat = 1.3
    /// Inching hump wavelength, as a multiple of `thickness`.
    var gaitWavelengthRatio: CGFloat = 15
    /// How fast the inching hump travels along the body.
    var gaitSpeed: Double = 1.4
    /// Within-stride dwell: 0 = a smooth constant crawl, higher = a real
    /// inchworm's gather-then-lunge. It slows to bunch up, then springs.
    var gaitStepiness: Double = 0.35
    /// Slow wander in crawl speed so the strides never settle into an obvious
    /// loop (0 = perfectly periodic).
    var gaitDrift: Double = 0.12

    /// The lively crawler used while travelling (the splash).
    static let standard = Worm()

    /// The same worm, idling: the full hump amount, but moving ~1/10th as fast —
    /// a slow, deep breathing motion for when it's just sitting there (loaders,
    /// the greeting) instead of actively crawling.
    static let calm = Worm(
        gaitHeightRatio: 2.6,
        gaitSpeed: 5.0,
        gaitStepiness: 0.1,
        gaitDrift: 0.06
    )

    /// The learned/snacking worm used through onboarding and home. Keeping this
    /// definition here makes the app share the exact same body language instead
    /// of each surface re-creating the mascot's movement constants.
    static let snacking = Worm(
        wobbleRatio: 0.06,
        gaitHeightRatio: 0.3,
        gaitSpeed: 2.4,
        gaitStepiness: 0.06,
        gaitDrift: 0.02
    )

    /// A short disturbance that travels away from one point on the body. The
    /// home worm uses these for touch reactions, so they deform the same
    /// centerline as the rest of the mascot's motion.
    struct Wiggle: Identifiable {
        let id = UUID()
        let startedAt: Double
        /// Position along the body: 0 is tail, 1 is head.
        let origin: Double
        /// Caller-controlled, bounded excitement multiplier.
        let strength: Double
    }
}

extension Worm {
    /// Draws the worm flowing along `centerline`. `gaitWeights`, if provided, is
    /// a per-point 0…1 mask of how much inching gait to apply (nil = full gait
    /// everywhere, e.g. a loader). `time` drives the gait and the breathing.
    func draw(
        in context: GraphicsContext,
        centerline raw: [CGPoint],
        time: Double,
        gaitWeights: [Double]? = nil,
        wiggles: [Wiggle] = []
    ) {
        let pts = Self.smoothed(raw, passes: 2)
        let n = pts.count
        guard n >= 2 else { return }

        let wobbleAmp = Double(thickness * wobbleRatio)
        let gaitAmp = Double(thickness * gaitHeightRatio)
        let gaitK = (2 * Double.pi) / Double(max(1, thickness * gaitWavelengthRatio))

        // The stride clock. NOTE: `time` is seconds-since-2001 (~8e8), so it must
        // only ever be multiplied by a CONSTANT rate. Multiplying it by a varying
        // factor amplifies that factor's drift into a runaway phase rate (the old
        // bug that made the gait spin no matter how low gaitSpeed was). Drift and
        // step are therefore bounded ADDITIVE terms.
        let basePhase = time * gaitSpeed
        let drift = gaitDrift * sin(time * 0.05)
        let gaitPhase = basePhase - gaitStepiness * sin(basePhase) + drift
        let breath = 0.9 + 0.1 * sin(time * 0.8 + 0.5)

        var arc = [Double](repeating: 0, count: n)
        for i in 1..<n {
            arc[i] = arc[i - 1] + Double(hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y))
        }

        var line: [CGPoint] = []
        line.reserveCapacity(n)

        for i in 0..<n {
            let localU = Double(i) / Double(n - 1)
            let endTaper = sin(localU * .pi)   // fade offsets to nothing at head & tail

            // Normal and straightness from a small window, so offsets vary
            // smoothly and DON'T whip around at sharp corners.
            let pa = pts[max(0, i - 2)]
            let pb = pts[min(n - 1, i + 2)]
            let dx = Double(pb.x - pa.x), dy = Double(pb.y - pa.y)
            let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
            let nx = -dy / len, ny = dx / len
            let straight = Self.straightness(pts, i)

            let s = arc[i]
            let wob = (sin(s * 0.020 + 1.3) * 1.0
                       + sin(s * 0.061 + 2.4) * 0.5
                       + sin(time * 0.5 + Double(i) * 0.2) * 0.55)
                * wobbleAmp * endTaper * straight * breath
            var x = Double(pts[i].x) + nx * wob
            var y = Double(pts[i].y) + ny * wob

            // Inching gait: a hump traveling along the body, bulging to one
            // consistent side of the path (-normal). Critically, this never
            // flips direction per-point — a per-point flip tears the body apart
            // where the path curves. Suppressed at corners (via straight).
            let weight = gaitWeights.map { $0[min(i, $0.count - 1)] } ?? 1.0
            if weight > 0 {
                // A smooth one-sided bump: (0.5 + 0.5·sin)² has zero slope at its
                // base, so the body eases into each hump with no hard kink where
                // the hump begins (unlike max(0, sin), which corners there).
                let bump = 0.5 + 0.5 * sin(s * gaitK - gaitPhase)
                let lift = gaitAmp * bump * bump * weight * endTaper * (0.4 + 0.6 * straight)
                x += -nx * lift
                y += -ny * lift
            }

            // Twin, single-lobe wavefronts start at the touch point and travel
            // toward both the head and tail. Cap their sum so a tap barrage
            // stays juicy without pulling the body apart.
            var ripple = 0.0
            for wiggle in wiggles {
                let age = time - wiggle.startedAt
                guard age >= 0, age < 0.62 else { continue }
                let distance = abs(localU - wiggle.origin)
                let front = age * 1.55
                let width = 0.12 + age * 0.04
                let envelope = exp(-pow((distance - front) / width, 2))
                ripple += envelope * wiggle.strength
            }
            ripple = min(ripple, 1.2)
            x += nx * ripple * Double(thickness) * 0.42 * endTaper * straight
            y += ny * ripple * Double(thickness) * 0.42 * endTaper * straight

            line.append(CGPoint(x: x, y: y))
        }

        WormBody.draw(context, centerline: line, maxWidth: thickness, color: color, eyeColor: eyeColor)
    }

    /// A densely sampled straight resting track. Large worms need more samples
    /// than the tiny onboarding seed; otherwise the gait bends the tube through a
    /// visibly segmented polyline.
    static func straightCenterline(center: CGPoint, length: CGFloat) -> [CGPoint] {
        let steps = max(18, Int((length / 4).rounded(.up)))
        let x0 = center.x - length / 2
        return (0...steps).map {
            CGPoint(x: x0 + length * CGFloat($0) / CGFloat(steps), y: center.y)
        }
    }

    /// Light smoothing so hard corners (e.g. the angular "r") round off the way
    /// a real worm body would, instead of kinking.
    private static func smoothed(_ pts: [CGPoint], passes: Int) -> [CGPoint] {
        guard pts.count >= 3, passes > 0 else { return pts }
        var current = pts
        for _ in 0..<passes {
            var next = current
            for i in 1..<(current.count - 1) {
                next[i] = CGPoint(
                    x: current[i - 1].x * 0.25 + current[i].x * 0.5 + current[i + 1].x * 0.25,
                    y: current[i - 1].y * 0.25 + current[i].y * 0.5 + current[i + 1].y * 0.25
                )
            }
            current = next
        }
        return current
    }

    /// 1 where the path runs straight, easing to 0 at a sharp turn.
    private static func straightness(_ pts: [CGPoint], _ i: Int) -> Double {
        guard i > 0, i < pts.count - 1 else { return 1 }
        let ax = Double(pts[i].x - pts[i - 1].x), ay = Double(pts[i].y - pts[i - 1].y)
        let bx = Double(pts[i + 1].x - pts[i].x), by = Double(pts[i + 1].y - pts[i].y)
        let la = max(0.0001, (ax * ax + ay * ay).squareRoot())
        let lb = max(0.0001, (bx * bx + by * by).squareRoot())
        return max(0, (ax * bx + ay * by) / (la * lb))
    }
}
