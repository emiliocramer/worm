import SwiftUI

/// THE worm. Outside the one-off splash transformation, every surface uses
/// `character`, `Size`, and `crawlCenterline`. Screens may place the worm and
/// trigger reactions, but they do not get to invent another body, size scale,
/// or way of crawling.
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

    /// The splash is deliberately its own word-drawing transformation.
    static let standard = Worm()

    /// The one persistent character used everywhere after the splash.
    static let character = Worm(
        wobbleRatio: 0.06,
        gaitHeightRatio: 0.3,
        gaitSpeed: 2.4,
        gaitStepiness: 0.06,
        gaitDrift: 0.02
    )

    /// The persistent body's dimensions. Growth changes this value; a screen
    /// never applies its own scale to make a second, local version of the worm.
    struct Size: Equatable {
        var length: CGFloat
        var thickness: CGFloat

        static let seed = Size(length: 15, thickness: 16)
        static let afterSelfie = Size(length: 30, thickness: 16)
        static let afterMusic = Size(length: 118, thickness: 16)

        /// Home begins at the exact size onboarding finished with. Every claimed
        /// meal adds one durable growth step, so relaunches never shrink him.
        static func earned(completedMeals: Int) -> Size {
            let meals = CGFloat(max(0, completedMeals))
            return Size(
                length: afterMusic.length + meals * 34,
                thickness: afterMusic.thickness + meals
            )
        }

        var afterNextMeal: Size {
            Size(length: length + 34, thickness: thickness + 1)
        }

        func interpolated(to target: Size, progress: CGFloat) -> Size {
            let p = min(max(progress, 0), 1)
            return Size(
                length: length + (target.length - length) * p,
                thickness: thickness + (target.thickness - thickness) * p
            )
        }
    }

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
    /// The character's one travelling gait. The body keeps one arc length while
    /// the rear anchors and the head reaches, the head pauses and plants, then
    /// the rear gathers beneath the arch. `route` is only where he is going;
    /// every proportion, pause, and irregularity belongs to the worm.
    static func crawlCenterline(
        along routePoints: [CGPoint],
        size: Size,
        progress rawProgress: Double,
        seed: Double,
        settlesAtEnd: Bool = false
    ) -> [CGPoint] {
        let route = CrawlRoute(routePoints)
        guard route.totalLength > 0.001 else {
            return straightCenterline(center: routePoints.first ?? .zero, length: size.length)
        }

        // A stride advances roughly one third of the body. Count is derived from
        // the route so a screen cannot make him take giant, stretchy steps.
        let targetAdvance = max(size.thickness * 1.15, size.length * 0.32)
        let strideCount = max(1, Int(ceil(route.totalLength / targetAdvance)))

        var distanceWeights: [CGFloat] = []
        var timeWeights: [Double] = []
        distanceWeights.reserveCapacity(strideCount)
        timeWeights.reserveCapacity(strideCount)
        for index in 0..<strideCount {
            distanceWeights.append(CGFloat(0.88 + crawlNoise(seed, index, 0) * 0.24))
            let occasionalLinger = crawlNoise(seed, index, 1) > 0.82 ? 0.28 : 0
            timeWeights.append(0.86 + crawlNoise(seed, index, 2) * 0.28 + occasionalLinger)
        }

        let distanceWeightTotal = distanceWeights.reduce(0, +)
        let timeWeightTotal = timeWeights.reduce(0, +)
        let progress = min(max(rawProgress, 0), 1)
        let timeTarget = progress * timeWeightTotal

        var strideIndex = strideCount - 1
        var elapsedWeight = 0.0
        for index in 0..<strideCount {
            let end = elapsedWeight + timeWeights[index]
            if timeTarget < end || index == strideCount - 1 {
                strideIndex = index
                break
            }
            elapsedWeight = end
        }
        let localTime = min(max(
            (timeTarget - elapsedWeight) / max(timeWeights[strideIndex], 0.001),
            0
        ), 1)

        var distanceBefore: CGFloat = 0
        if strideIndex > 0 {
            distanceBefore = distanceWeights[..<strideIndex].reduce(0, +)
        }
        let centerStart = route.totalLength * distanceBefore / distanceWeightTotal
        let advance = route.totalLength * distanceWeights[strideIndex] / distanceWeightTotal

        // Each beat gets its own quiet timing. The planted pauses are real time,
        // not just easing at the ends of one continuous slide.
        let rearPause = 0.06 + crawlNoise(seed, strideIndex, 3) * 0.06
        let reachDuration = 0.30 + crawlNoise(seed, strideIndex, 4) * 0.06
        let frontPause = 0.09 + crawlNoise(seed, strideIndex, 5) * 0.06
        let gatherDuration = 0.28 + crawlNoise(seed, strideIndex, 6) * 0.06
        let reachEnd = rearPause + reachDuration
        let frontPauseEnd = reachEnd + frontPause
        let gatherEnd = min(0.96, frontPauseEnd + gatherDuration)

        let fullSeparation = size.length * 0.96
        let gatheredSeparation = max(size.length * 0.56, fullSeparation - advance)
        var tailDistance = centerStart - gatheredSeparation / 2
        var headDistance = centerStart + gatheredSeparation / 2

        if localTime < rearPause {
            // Rear planted. Hold the gathered arch before committing forward.
        } else if localTime < reachEnd {
            let reach = smootherstep((localTime - rearPause) / reachDuration)
            headDistance += advance * CGFloat(reach)
        } else if localTime < frontPauseEnd {
            // Head planted. A tiny forward test keeps the pause alive without
            // changing the worm's apparent length.
            let pause = (localTime - reachEnd) / frontPause
            let test = sin(pause * .pi) * min(Double(size.thickness) * 0.08, Double(advance) * 0.025)
            headDistance += advance + CGFloat(test)
        } else {
            headDistance += advance
            let gather = smootherstep((localTime - frontPauseEnd) / max(gatherEnd - frontPauseEnd, 0.001))
            tailDistance += advance * CGFloat(gather)
        }

        // When a finite crawl ends, relax from the final gathered hold into the
        // same straight resting body without a one-frame shape pop.
        if settlesAtEnd, strideIndex == strideCount - 1, localTime > gatherEnd {
            let relax = smootherstep((localTime - gatherEnd) / max(1 - gatherEnd, 0.001))
            let currentSeparation = headDistance - tailDistance
            let targetSeparation = size.length
            let halfExpansion = (targetSeparation - currentSeparation) * CGFloat(relax) / 2
            tailDistance -= halfExpansion
            headDistance += halfExpansion
        }

        let archSkew = (crawlNoise(seed, strideIndex, 7) - 0.5) * 0.10
        return constantLengthBody(
            on: route,
            tailDistance: tailDistance,
            headDistance: headDistance,
            bodyLength: size.length,
            archSkew: archSkew
        )
    }

    /// Finds the single-lobe arch whose sampled arc length matches the worm's
    /// persistent body length. Reaching and gathering therefore reshape him;
    /// they never stretch or shrink him.
    private static func constantLengthBody(
        on route: CrawlRoute,
        tailDistance: CGFloat,
        headDistance: CGFloat,
        bodyLength: CGFloat,
        archSkew: Double
    ) -> [CGPoint] {
        let steps = max(28, Int((bodyLength / 3).rounded(.up)))

        func points(amplitude: CGFloat) -> [CGPoint] {
            (0...steps).map { index in
                let u = CGFloat(index) / CGFloat(steps)
                let distance = tailDistance + (headDistance - tailDistance) * u
                let base = route.point(at: distance)
                let normal = route.normal(at: distance)
                let warped = min(max(Double(u) + archSkew * Double(u * (1 - u)), 0), 1)
                let lift = amplitude * CGFloat(sin(warped * .pi))
                return CGPoint(x: base.x - normal.x * lift, y: base.y - normal.y * lift)
            }
        }

        var low: CGFloat = 0
        var high = bodyLength * 0.62
        for _ in 0..<14 {
            let middle = (low + high) / 2
            if polylineLength(points(amplitude: middle)) < bodyLength {
                low = middle
            } else {
                high = middle
            }
        }
        return points(amplitude: (low + high) / 2)
    }

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

    private static func smootherstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    private static func crawlNoise(_ seed: Double, _ stride: Int, _ channel: Int) -> Double {
        let raw = sin(seed * 12.9898 + Double(stride) * 78.233 + Double(channel) * 37.719) * 43_758.5453
        return raw - floor(raw)
    }

    private static func polylineLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { partial, pair in
            partial + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }

    private struct CrawlRoute {
        let points: [CGPoint]
        let cumulative: [CGFloat]
        let totalLength: CGFloat
        let isClosed: Bool

        init(_ raw: [CGPoint]) {
            let fallback = raw.first ?? .zero
            let usable = raw.count >= 2 ? raw : [fallback, CGPoint(x: fallback.x + 0.001, y: fallback.y)]
            points = usable
            var lengths = [CGFloat](repeating: 0, count: usable.count)
            for index in 1..<usable.count {
                lengths[index] = lengths[index - 1]
                    + hypot(usable[index].x - usable[index - 1].x, usable[index].y - usable[index - 1].y)
            }
            cumulative = lengths
            totalLength = lengths.last ?? 0
            isClosed = hypot(usable.last!.x - usable.first!.x, usable.last!.y - usable.first!.y) < 1
        }

        func point(at rawDistance: CGFloat) -> CGPoint {
            guard totalLength > 0.001 else { return points[0] }
            var distance = rawDistance
            if isClosed {
                distance = distance.truncatingRemainder(dividingBy: totalLength)
                if distance < 0 { distance += totalLength }
            } else if distance < 0 {
                let direction = Self.unit(from: points[1], subtracting: points[0])
                return CGPoint(x: points[0].x + direction.x * distance, y: points[0].y + direction.y * distance)
            } else if distance > totalLength {
                let direction = Self.unit(from: points[points.count - 1], subtracting: points[points.count - 2])
                let extra = distance - totalLength
                return CGPoint(x: points.last!.x + direction.x * extra, y: points.last!.y + direction.y * extra)
            }

            var low = 0
            var high = cumulative.count - 1
            while low + 1 < high {
                let middle = (low + high) / 2
                if cumulative[middle] <= distance { low = middle }
                else { high = middle }
            }
            let segmentLength = max(cumulative[high] - cumulative[low], 0.0001)
            let t = (distance - cumulative[low]) / segmentLength
            return CGPoint(
                x: points[low].x + (points[high].x - points[low].x) * t,
                y: points[low].y + (points[high].y - points[low].y) * t
            )
        }

        func normal(at distance: CGFloat) -> CGPoint {
            let epsilon = max(0.8, totalLength * 0.0008)
            let before = point(at: distance - epsilon)
            let after = point(at: distance + epsilon)
            let direction = Self.unit(from: after, subtracting: before)
            return CGPoint(x: -direction.y, y: direction.x)
        }

        private static func unit(from point: CGPoint, subtracting other: CGPoint) -> CGPoint {
            let dx = point.x - other.x
            let dy = point.y - other.y
            let length = max(0.0001, hypot(dx, dy))
            return CGPoint(x: dx / length, y: dy / length)
        }
    }
}
