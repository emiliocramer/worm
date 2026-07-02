import SwiftUI

/// Splash: a single thin worm crawls in from the left, then *becomes* the word
/// "worm" by extending its body along the letterforms, then contracts and
/// slithers off to the right before crossfading into the app.
///
/// The worm is not separate from the writing — it is the writing. The whole
/// thing is one continuous travel path (lead-in line → the word → lead-out
/// line); the worm is the trimmed segment `[tail, head]` of it. As the head
/// advances through the word while the tail stays anchored at the word's start,
/// the body stretches to exactly the length the word needs.
struct WormSplashView: View {
    var onFinished: () -> Void

    // Phase durations (seconds).
    private let enter: Double = 2.1
    private let become: Double = 2.0
    private let exitDuration: Double = 1.1
    private let tailPad: Double = 0.3

    private var total: Double { enter + become + exitDuration + tailPad }

    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let rect = CGRect(origin: .zero, size: geo.size)

            let word = WormWord(widthFraction: 0.82).path(in: rect)
            let wordStart = word.trimmedPath(from: 0, to: 0.0008).currentPoint
                ?? CGPoint(x: width * 0.2, y: height / 2)
            let wordEnd = word.currentPoint
                ?? CGPoint(x: width * 0.8, y: height / 2)
            let wordLen = Self.length(of: word)

            // Lead-in: the worm slithers in from off the left edge with a gentle
            // S, descends toward the center, then bottoms out and approaches the
            // word horizontally from the left so the tail trails behind him. He
            // starts fully off-screen so the first you see is him slithering on,
            // not popping into the middle.
            let entryStart = CGPoint(x: -width * 0.22, y: height * 0.34)
            let leadIn: Path = {
                var path = Path()
                path.move(to: entryStart)
                path.addCurve(
                    to: wordStart,
                    control1: CGPoint(x: width * 0.16, y: height * 0.30),
                    control2: CGPoint(x: wordStart.x - width * 0.22, y: wordStart.y)
                )
                return path
            }()

            // Lead-out: a straight line off the right edge, as long as the word so
            // the worm can keep a constant length as it slithers away.
            let leadInLen = Self.length(of: leadIn)
            let rightOff = wordEnd.x + wordLen
            let totalLen = leadInLen + wordLen + wordLen

            let a = leadInLen / totalLen                  // fraction where the word starts
            let b = (leadInLen + wordLen) / totalLen      // fraction where the word ends
            let bodyLen = min(120, leadInLen * 0.75)      // worm length while travelling in
            let bodyFrac = bodyLen / totalLen

            let travel: Path = {
                var path = leadIn
                path.addPath(word)
                path.addLine(to: CGPoint(x: rightOff, y: wordEnd.y))
                return path
            }()

            // Dense, arc-length-uniform sample of the whole travel path, computed
            // once per layout. Each frame we slice out the worm's [tail, head]
            // span from this instead of re-trimming every point.
            let samples = Self.samplePolyline(travel, count: 500, fallback: wordStart)

            // The one shared worm — only its size and eye are set for this context.
            let worm: Worm = {
                var w = Worm.standard
                w.thickness = max(5, width * 0.017)
                w.eyeColor = paper
                return w
            }()

            TimelineView(.animation) { timeline in
                let t = max(0, timeline.date.timeIntervalSince(start))
                let seg = segment(at: t, a: a, b: b, bodyFrac: bodyFrac)

                Canvas { context, _ in
                    let slice = bodySlice(samples: samples, tail: seg.tail, head: seg.head, aFrac: a, bFrac: b)
                    guard slice.points.count >= 2 else { return }
                    worm.draw(in: context, centerline: slice.points, time: t, gaitWeights: slice.weights)
                }
                .background(paper.ignoresSafeArea())
            }
        }
        .opacity(finished ? 0 : 1)
        .task {
            try? await Task.sleep(for: .seconds(total))
            withAnimation(.easeOut(duration: 0.45)) { finished = true }
            try? await Task.sleep(for: .seconds(0.45))
            onFinished()
        }
    }

    private var paper: Color {
        Color(red: 0.97, green: 0.96, blue: 0.93)
    }

    /// The worm's `[tail, head]` segment (in travel-path fractions) at time `t`.
    private func segment(at t: Double, a: CGFloat, b: CGFloat, bodyFrac: CGFloat) -> (tail: CGFloat, head: CGFloat) {
        if t < enter {
            // Inchworm locomotion along the lead-in: each stride the head reaches
            // forward (body extends) then the tail gathers up to it (body
            // contracts), netting forward progress — instead of a rigid glide.
            // Whole number of strides so it ends exactly at (a - bodyFrac, a),
            // matching the start of the writing phase with no pop.
            let f = t / enter
            let strides = 3.0
            let s = f * strides
            let k = (s).rounded(.down)
            let ph = s - k
            let headProg = min(1, (k + ease(ph / 0.5)) / strides)        // reaches in first half
            let tailProg = min(1, (k + ease((ph - 0.5) / 0.5)) / strides) // gathers in second half
            return (lerp(0, a - bodyFrac, tailProg), lerp(bodyFrac, a, headProg))
        }
        if t < enter + become {
            // Tail anchors at the word start; the head writes the word, so the
            // body extends to the word's full length.
            let f = ease((t - enter) / become)
            return (lerp(a - bodyFrac, a, f), lerp(a, b, f))
        }
        if t < enter + become + exitDuration {
            // Tail catches the head (inchworm contraction) as he slides off right.
            let f = ease((t - enter - become) / exitDuration)
            return (lerp(a, 1, f), lerp(b, 1, f))
        }
        return (1, 1)
    }

    private func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ f: Double) -> CGFloat {
        a + (b - a) * CGFloat(f)
    }

    /// Approximate arc length of a path by sampling points along it.
    private static func length(of path: Path, samples: Int = 120) -> CGFloat {
        var previous = path.trimmedPath(from: 0, to: 0.0001).currentPoint ?? .zero
        var total: CGFloat = 0
        var i = 1
        while i <= samples {
            let f = CGFloat(i) / CGFloat(samples)
            let point = path.trimmedPath(from: 0, to: f).currentPoint ?? previous
            total += hypot(point.x - previous.x, point.y - previous.y)
            previous = point
            i += 1
        }
        return total
    }

    /// Arc-length-uniform sample of a path: `count + 1` points from start to end.
    private static func samplePolyline(_ path: Path, count: Int, fallback: CGPoint) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(count + 1)
        for i in 0...count {
            let f = max(CGFloat(i) / CGFloat(count), 0.0001)
            result.append(path.trimmedPath(from: 0, to: f).currentPoint ?? fallback)
        }
        return result
    }

    /// Slices the worm's `[tail, head]` span out of the sampled travel path and
    /// returns it together with a per-point gait mask: 1 where the worm is
    /// crawling (the lead-in / lead-out), 0 where it's lying still as the written
    /// word. All shape and motion is the `Worm`'s job, not this view's.
    private func bodySlice(
        samples: [CGPoint],
        tail: CGFloat,
        head: CGFloat,
        aFrac: CGFloat,
        bFrac: CGFloat
    ) -> (points: [CGPoint], weights: [Double]) {
        let count = samples.count - 1
        guard count >= 2, head > tail else { return ([], []) }

        let lo = max(0, min(Int((tail * CGFloat(count)).rounded(.down)), count))
        let hi = max(lo + 1, min(Int((head * CGFloat(count)).rounded(.up)), count))
        let band: CGFloat = 0.04

        var points: [CGPoint] = []
        var weights: [Double] = []
        points.reserveCapacity(hi - lo + 1)
        weights.reserveCapacity(hi - lo + 1)

        for i in lo...hi {
            points.append(samples[i])
            let frac = CGFloat(i) / CGFloat(count)
            let weight: Double
            if frac < aFrac {
                weight = Double(smoothstep01((aFrac - frac) / band))
            } else if frac > bFrac {
                weight = Double(smoothstep01((frac - bFrac) / band))
            } else {
                weight = 0
            }
            weights.append(weight)
        }
        return (points, weights)
    }

    private func smoothstep01(_ x: CGFloat) -> CGFloat {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

#Preview {
    WormSplashView(onFinished: {})
}
