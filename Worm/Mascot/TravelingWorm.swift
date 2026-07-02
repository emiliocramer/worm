import SwiftUI

/// THE way the worm moves — steering at an even cruise speed, with a
/// trail-following body.
///
/// The head has a heading; it turns toward `target` at a limited rate and always
/// moves FORWARD, so it curves toward the goal like a worm — it never reverses
/// into itself (no fold) and never loops out the wrong way first. It travels at
/// a constant cruise speed that gently ramps up at the start and down on arrival,
/// so the pace is even — no darting. The body trails along the head's path and
/// relaxes into a clean line at rest; the `Worm` gait inches it the whole time.
///
/// This is the single definition of worm locomotion. Change it here and every
/// move, everywhere, changes with it.
///
/// Fills its container; `target` is the head's destination in that space.
struct TravelingWorm: View {
    var target: CGPoint
    var color: Color = .black
    var eyeColor: Color? = nil
    var thickness: CGFloat = 11
    /// Resting body length, in points.
    var bodyLength: CGFloat = 92
    /// Even cruise speed, points per second.
    var cruiseSpeed: CGFloat = 95
    /// Max turn rate, radians per second. Kept low so the turn radius
    /// (≈ speed / maxTurn) stays comparable to the body length — otherwise the
    /// body wraps a too-tight turn into a coil.
    var maxTurn: Double = 1.7

    private static let nodeCount = 26
    private static let arriveRadius: CGFloat = 4

    @State private var trail: [CGPoint] = []
    @State private var heading = CGVector(dx: 1, dy: 0)
    @State private var clock: Double = 0
    @State private var moveElapsed: Double = 0
    /// 0 while crawling, eases to 1 at rest — straightens the body.
    @State private var settle: Double = 1

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var segmentLength: CGFloat { bodyLength / CGFloat(Self.nodeCount - 1) }

    var body: some View {
        Canvas { context, _ in
            let nodes = restingBlendedNodes()
            guard nodes.count >= 2 else { return }
            var worm = Worm.calm
            worm.thickness = thickness
            worm.color = color
            worm.eyeColor = eyeColor
            worm.draw(in: context, centerline: nodes.reversed(), time: clock)
        }
        .onAppear {
            if trail.isEmpty {
                trail = (0..<(Self.nodeCount * 2)).map {
                    CGPoint(x: target.x - CGFloat($0) * segmentLength * 0.5, y: target.y)
                }
            }
        }
        .onChange(of: target) { _, _ in moveElapsed = 0 }   // restart the ramp-in
        .onReceive(ticker) { _ in step(dt: 1.0 / 60.0) }
    }

    private func step(dt: Double) {
        guard let head = trail.first else { return }
        clock += dt

        let toX = target.x - head.x, toY = target.y - head.y
        let dist = hypot(toX, toY)

        if dist <= Self.arriveRadius {
            settle = min(1, settle + dt / 0.45)
            return
        }
        settle = max(0, settle - dt / 0.2)
        moveElapsed += dt

        // Steer the heading toward the target, limited by the turn rate.
        let desired = atan2(toY, toX)
        let current = atan2(heading.dy, heading.dx)
        var diff = desired - current
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        let turn = max(-maxTurn * dt, min(maxTurn * dt, diff))
        let angle = current + turn
        heading = CGVector(dx: cos(angle), dy: sin(angle))

        // Even cruise speed: ramp up over the first beat, ramp down on approach.
        let rampIn = min(1.0, moveElapsed / 0.4)
        let rampOut = min(1.0, Double(dist) / 50.0)
        let speed = cruiseSpeed * CGFloat(rampIn * rampOut)
        let stepDist = min(dist, speed * CGFloat(dt))
        let newHead = CGPoint(x: head.x + heading.dx * stepDist, y: head.y + heading.dy * stepDist)

        var t = trail
        if hypot(newHead.x - head.x, newHead.y - head.y) > 1.0 {
            t.insert(newHead, at: 0)
        } else {
            t[0] = newHead
        }
        trail = trimmed(t)
    }

    private func trimmed(_ t: [CGPoint]) -> [CGPoint] {
        var kept = 1
        var acc: CGFloat = 0
        while kept < t.count {
            acc += hypot(t[kept].x - t[kept - 1].x, t[kept].y - t[kept - 1].y)
            kept += 1
            if acc > bodyLength * 1.3 { break }
        }
        return Array(t.prefix(kept))
    }

    /// Body nodes from the trail, blended toward a straight line along the heading
    /// as the worm settles — a clean worm at rest, not a hooked trail.
    private func restingBlendedNodes() -> [CGPoint] {
        let trailNodes = bodyNodes()
        guard trailNodes.count >= 3 else { return trailNodes }
        let b = CGFloat(ease(settle))
        guard b > 0.001 else { return trailNodes }

        let head = trailNodes[0]
        return trailNodes.enumerated().map { i, node in
            let straight = CGPoint(x: head.x - heading.dx * CGFloat(i) * segmentLength,
                                   y: head.y - heading.dy * CGFloat(i) * segmentLength)
            return CGPoint(x: node.x * (1 - b) + straight.x * b,
                           y: node.y * (1 - b) + straight.y * b)
        }
    }

    private func bodyNodes() -> [CGPoint] {
        guard let head = trail.first else { return [] }
        var nodes: [CGPoint] = [head]
        var prev = head
        var acc: CGFloat = 0
        var i = 1
        while nodes.count < Self.nodeCount && i < trail.count {
            let next = trail[i]
            let dx = next.x - prev.x, dy = next.y - prev.y
            let d = hypot(dx, dy)
            if d <= 0.0001 { i += 1; continue }
            if acc + d >= segmentLength {
                let f = (segmentLength - acc) / d
                let node = CGPoint(x: prev.x + dx * f, y: prev.y + dy * f)
                nodes.append(node)
                prev = node
                acc = 0
            } else {
                acc += d
                prev = next
                i += 1
            }
        }
        while nodes.count < Self.nodeCount {
            let a = nodes[nodes.count - 1]
            let b = nodes.count >= 2 ? nodes[nodes.count - 2] : CGPoint(x: a.x + 1, y: a.y)
            let dx = a.x - b.x, dy = a.y - b.y
            let d = max(0.0001, hypot(dx, dy))
            nodes.append(CGPoint(x: a.x + dx / d * segmentLength, y: a.y + dy / d * segmentLength))
        }
        return nodes
    }

    private func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
