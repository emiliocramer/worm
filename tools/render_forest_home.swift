import AppKit
import CoreGraphics

// Reproducible source artwork for Worm's home. The scene is intentionally
// limited to a small, earthy screen-print palette. Organic silhouettes,
// overprinted texture, and stippled light keep it tactile without fighting the
// mascot's crisp black body.

private let width = 1_290
private let height = 2_796
private let size = CGSize(width: width, height: height)

private struct Random {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat((state >> 11) & 0x1f_ffff) / CGFloat(0x1f_ffff)
    }

    mutating func range(_ bounds: ClosedRange<CGFloat>) -> CGFloat {
        bounds.lowerBound + next() * (bounds.upperBound - bounds.lowerBound)
    }
}

private extension CGColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: alpha
        )
    }
}

private enum Palette {
    static let paper = CGColor.hex(0xF7F2D8)
    static let sunlight = CGColor.hex(0xEFE8A8)
    static let mist = CGColor.hex(0xC9DEB4)
    static let sage = CGColor.hex(0x7FA46D)
    static let moss = CGColor.hex(0x3E704A)
    static let deepMoss = CGColor.hex(0x173F36)
    static let bark = CGColor.hex(0x5D4435)
    static let barkLight = CGColor.hex(0xA87950)
    static let beech = CGColor.hex(0x66735E)
    static let beechLight = CGColor.hex(0xA8AE82)
    static let earth = CGColor.hex(0xBEA45E)
    static let lichen = CGColor.hex(0xDDE5A7)
    static let stone = CGColor.hex(0x768A7B)
    static let ink = CGColor.hex(0x122E29)
}

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x * size.width, y: y * size.height)
}

private func smoothBlob(
    center: CGPoint,
    radiusX: CGFloat,
    radiusY: CGFloat,
    count: Int,
    randomness: CGFloat,
    seed: UInt64
) -> CGPath {
    var random = Random(seed: seed)
    var points: [CGPoint] = []
    for index in 0..<count {
        let angle = CGFloat(index) / CGFloat(count) * .pi * 2
        let radius = 1 + random.range(-randomness...randomness)
        points.append(CGPoint(
            x: center.x + cos(angle) * radiusX * radius,
            y: center.y + sin(angle) * radiusY * radius
        ))
    }

    let path = CGMutablePath()
    guard let first = points.first else { return path }
    let previous = points.last!
    path.move(to: CGPoint(x: (previous.x + first.x) / 2, y: (previous.y + first.y) / 2))
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        let midpoint = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
        path.addQuadCurve(to: midpoint, control: current)
    }
    path.closeSubpath()
    return path
}

private func fill(_ path: CGPath, color: CGColor, in context: CGContext) {
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
}

private func stroke(
    _ path: CGPath,
    color: CGColor,
    width: CGFloat,
    in context: CGContext,
    dash: [CGFloat] = []
) {
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    if !dash.isEmpty { context.setLineDash(phase: 0, lengths: dash) }
    context.strokePath()
    context.restoreGState()
}

private func leftOakPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: point(-0.06, 0.655))
    p.addCurve(
        to: point(0.055, -0.06),
        control1: point(-0.015, 0.49),
        control2: point(0.015, 0.18)
    )
    p.addCurve(
        to: point(0.155, -0.06),
        control1: point(0.095, -0.01),
        control2: point(0.13, -0.04)
    )
    p.addCurve(
        to: point(0.15, 0.48),
        control1: point(0.13, 0.14),
        control2: point(0.18, 0.34)
    )
    p.addCurve(
        to: point(0.21, 0.655),
        control1: point(0.14, 0.56),
        control2: point(0.185, 0.62)
    )
    p.closeSubpath()
    return p
}

private func rightBeechPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: point(0.83, 0.682))
    p.addCurve(to: point(0.85, 0.30), control1: point(0.86, 0.57), control2: point(0.835, 0.43))
    p.addCurve(to: point(0.815, -0.06), control1: point(0.86, 0.16), control2: point(0.83, 0.03))
    p.addCurve(to: point(0.90, -0.06), control1: point(0.84, -0.035), control2: point(0.875, -0.05))
    p.addCurve(to: point(0.93, 0.28), control1: point(0.905, 0.08), control2: point(0.945, 0.18))
    p.addCurve(to: point(0.995, 0.682), control1: point(0.92, 0.44), control2: point(0.96, 0.60))
    p.closeSubpath()
    return p
}

private func rightBeechCompanionPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: point(0.935, 0.675))
    p.addCurve(to: point(0.955, 0.23), control1: point(0.97, 0.53), control2: point(0.95, 0.36))
    p.addCurve(to: point(0.965, -0.05), control1: point(0.94, 0.11), control2: point(0.95, 0.02))
    p.addCurve(to: point(1.055, -0.05), control1: point(0.99, -0.03), control2: point(1.025, -0.04))
    p.addCurve(to: point(1.09, 0.675), control1: point(1.025, 0.20), control2: point(1.07, 0.49))
    p.closeSubpath()
    return p
}

private func branch(
    from start: CGPoint,
    via control: CGPoint,
    to end: CGPoint,
    color: CGColor,
    width: CGFloat,
    in context: CGContext
) {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = max(1, hypot(dx, dy))
    let dir = CGPoint(x: dx / length, y: dy / length)
    let normal = CGPoint(x: -dir.y, y: dir.x)
    let halfBase = width / 2
    let halfTip = max(4, width * 0.09)
    // A limb grows out of the trunk, it isn't glued on: the base sits back into
    // the wood and flares wider, so the join reads as a continuous shoulder.
    let flare = width * 0.6
    let baseBack = CGPoint(x: start.x - dir.x * flare * 0.7, y: start.y - dir.y * flare * 0.7)
    let baseHalf = halfBase + flare

    let path = CGMutablePath()
    path.move(to: CGPoint(x: baseBack.x + normal.x * baseHalf, y: baseBack.y + normal.y * baseHalf))
    // Concave shoulder into the straight limb, then out to the tip.
    path.addQuadCurve(
        to: CGPoint(x: end.x + normal.x * halfTip, y: end.y + normal.y * halfTip),
        control: CGPoint(x: control.x + normal.x * width * 0.30, y: control.y + normal.y * width * 0.30)
    )
    path.addQuadCurve(
        to: CGPoint(x: end.x - normal.x * halfTip, y: end.y - normal.y * halfTip),
        control: CGPoint(x: end.x + dir.x * halfTip * 1.5, y: end.y + dir.y * halfTip * 1.5)
    )
    path.addQuadCurve(
        to: CGPoint(x: baseBack.x - normal.x * baseHalf, y: baseBack.y - normal.y * baseHalf),
        control: CGPoint(x: control.x - normal.x * width * 0.30, y: control.y - normal.y * width * 0.30)
    )
    path.closeSubpath()
    fill(path, color: color, in: context)
}

private func leafCluster(
    center: CGPoint,
    scale: CGFloat,
    seed: UInt64,
    color: CGColor,
    in context: CGContext
) {
    var random = Random(seed: seed)
    let cluster = smoothBlob(
        center: center,
        radiusX: 150 * scale,
        radiusY: 105 * scale,
        count: 14,
        randomness: 0.23,
        seed: seed
    )
    fill(cluster, color: color, in: context)

    context.saveGState()
    context.setBlendMode(.multiply)
    for _ in 0..<Int(22 * scale + 8) {
        let angle = random.range(0...(2 * .pi))
        let distance = sqrt(random.next())
        let x = center.x + cos(angle) * 135 * scale * distance
        let y = center.y + sin(angle) * 90 * scale * distance
        let length = random.range(12...30) * scale
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x - length * 0.45, y: y + length * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: x + length * 0.45, y: y - length * 0.18),
            control: CGPoint(x: x, y: y - length * 0.38)
        )
        stroke(path, color: Palette.deepMoss.copy(alpha: 0.22)!, width: max(2, 3 * scale), in: context)
    }
    context.restoreGState()
}

private func leafPath(center: CGPoint, length: CGFloat, width: CGFloat, angle: CGFloat) -> CGPath {
    let local = CGMutablePath()
    local.move(to: CGPoint(x: -length * 0.5, y: 0))
    local.addCurve(
        to: CGPoint(x: length * 0.5, y: 0),
        control1: CGPoint(x: -length * 0.08, y: -width * 0.72),
        control2: CGPoint(x: length * 0.32, y: -width * 0.40)
    )
    local.addCurve(
        to: CGPoint(x: -length * 0.5, y: 0),
        control1: CGPoint(x: length * 0.20, y: width * 0.60),
        control2: CGPoint(x: -length * 0.20, y: width * 0.48)
    )
    local.closeSubpath()
    var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
    return local.copy(using: &transform) ?? local
}

private func leafSpray(
    bounds: CGRect,
    count: Int,
    seed: UInt64,
    colors: [CGColor],
    slenderness: CGFloat,
    anchor: CGPoint,
    in context: CGContext
) {
    var random = Random(seed: seed)
    for index in 0..<count {
        // Bias toward the canopy mass (averaging two samples pulls points inward)
        // so leaves sit on the foliage instead of floating out in open air.
        let bx = (random.next() + random.next()) / 2
        let by = (random.next() + random.next()) / 2
        let center = CGPoint(
            x: bounds.minX + bx * bounds.width,
            y: bounds.minY + by * bounds.height
        )
        // Stragglers far from the canopy anchor fade out rather than reading as
        // hard confetti.
        let d = hypot(center.x - anchor.x, center.y - anchor.y)
        let falloff = max(0, 1 - d / (max(bounds.width, bounds.height) * 0.85))
        let alpha = (0.42 + 0.5 * falloff) * random.range(0.8...1.05)
        guard alpha > 0.22 else { continue }
        let length = random.range(24...54)
        let width = length * random.range((0.24 * slenderness)...(0.46 * slenderness))
        let angle = random.range((-CGFloat.pi)...CGFloat.pi)
        fill(
            leafPath(center: center, length: length, width: width, angle: angle),
            color: colors[index % colors.count].copy(alpha: min(1, alpha))!,
            in: context
        )
    }
}

private func oakKnot(at center: CGPoint, scale: CGFloat, in context: CGContext) {
    // A healed knot: concentric grain rings that the surrounding bark grew
    // around, tightening to a dark eye — not a flat oval pasted on the trunk.
    let rings: [(CGFloat, CGColor)] = [
        (1.00, Palette.deepMoss.copy(alpha: 0.32)!),
        (0.74, Palette.barkLight.copy(alpha: 0.42)!),
        (0.52, Palette.bark.copy(alpha: 0.85)!),
        (0.34, Palette.barkLight.copy(alpha: 0.40)!),
        (0.18, Palette.deepMoss.copy(alpha: 0.85)!),
    ]
    for (index, ring) in rings.enumerated() {
        // Each ring sits slightly lower than the last, giving the socket depth.
        let drop = CGFloat(index) * 2.2 * scale
        let blob = smoothBlob(
            center: CGPoint(x: center.x, y: center.y + drop),
            radiusX: 40 * scale * ring.0,
            radiusY: 27 * scale * ring.0,
            count: 12,
            randomness: 0.10,
            seed: 0x0A4 + UInt64(index)
        )
        fill(blob, color: ring.1, in: context)
    }
}

private func grassTuft(
    at base: CGPoint,
    scale: CGFloat,
    seed: UInt64,
    color: CGColor,
    in context: CGContext
) {
    var random = Random(seed: seed)
    let blades = 9 + Int(random.next() * 4)
    for index in 0..<blades {
        // Uneven spread + per-blade lean so the tuft never fans out symmetric.
        let spread = CGFloat(index) / CGFloat(blades - 1) * 2 - 1 + random.range(-0.16...0.16)
        let height = random.range(34...90) * scale * (1 - abs(spread) * 0.14)
        let start = CGPoint(x: base.x + spread * 22 * scale + random.range(-6...6) * scale, y: base.y)
        // Blades curve past vertical and sometimes cross their neighbours.
        let lean = spread * random.range(0.6...1.3) + random.range(-0.25...0.25)
        let end = CGPoint(x: start.x + lean * random.range(20...44) * scale, y: start.y - height)
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(
            to: end,
            control: CGPoint(x: start.x + lean * random.range(6...14) * scale, y: start.y - height * random.range(0.5...0.68))
        )
        stroke(path, color: color, width: max(2, random.range(2.6...5.4) * scale), in: context)
    }
}

private func fern(
    at base: CGPoint,
    scale: CGFloat,
    lean: CGFloat,
    color: CGColor,
    seed: UInt64,
    in context: CGContext
) {
    var random = Random(seed: seed)
    let length = 300 * scale

    // The rachis leans progressively harder toward the tip, so the frond arcs
    // over instead of standing like a mast.
    func rachis(_ t: CGFloat) -> CGPoint {
        let bend = lean * length * (0.45 * t + 0.55 * t * t)
        return CGPoint(x: base.x + bend, y: base.y - length * t)
    }

    let steps = 17
    let stem = CGMutablePath()
    stem.move(to: rachis(0))
    for s in 1...steps { stem.addLine(to: rachis(CGFloat(s) / CGFloat(steps))) }
    stroke(stem, color: color, width: max(3, 6 * scale), in: context)

    // Pinnae alternate strictly left/right (never mirrored pairs), shrink toward
    // the tip, and sweep forward — the anatomy that keeps a real frond from
    // reading as a machine-cut zipper.
    let dark = color.copy(alpha: 0.9)!
    for index in 1..<(steps - 1) {
        let t = CGFloat(index) / CGFloat(steps)
        let node = rachis(t)
        let side: CGFloat = index.isMultiple(of: 2) ? 1 : -1
        let span = ((1 - t) * 74 * scale + 9 * scale) * random.range(0.86...1.08)
        let sweep = 0.42 + 0.6 * t          // more upward tilt near the tip
        let tipPt = CGPoint(x: node.x + side * span * 0.96, y: node.y - span * sweep * 0.72)

        let pinna = CGMutablePath()
        pinna.move(to: node)
        pinna.addQuadCurve(to: tipPt, control: CGPoint(x: node.x + side * span * 0.5, y: node.y - span * 0.58))
        pinna.addQuadCurve(to: node, control: CGPoint(x: node.x + side * span * 0.40, y: node.y + span * 0.12))
        pinna.closeSubpath()
        fill(pinna, color: color, in: context)

        // A hair-thin midvein gives each leaflet its own spine.
        let vein = CGMutablePath()
        vein.move(to: node)
        vein.addQuadCurve(to: tipPt, control: CGPoint(x: node.x + side * span * 0.5, y: node.y - span * 0.44))
        stroke(vein, color: dark, width: max(1, 1.4 * scale), in: context)
    }

    // The tip curls over, the way a frond's growing point does.
    let tip = rachis(1)
    let curl = CGMutablePath()
    curl.move(to: tip)
    curl.addQuadCurve(
        to: CGPoint(x: tip.x + lean * 30 * scale, y: tip.y - 6 * scale),
        control: CGPoint(x: tip.x + lean * 6 * scale, y: tip.y - 26 * scale)
    )
    stroke(curl, color: color, width: max(2, 4 * scale), in: context)
}

/// A small tidy spray of leaves fanning around one direction — a sprig at the
/// end of a twig, not a random burst. `along` is the outward angle in radians.
private func leafSprig(
    at tip: CGPoint,
    along: CGFloat,
    count: Int,
    scale: CGFloat,
    seed: UInt64,
    colors: [CGColor],
    in context: CGContext
) {
    var random = Random(seed: seed)
    for index in 0..<count {
        let frac = CGFloat(index) / CGFloat(max(1, count - 1)) - 0.5   // -0.5...0.5
        let angle = along + frac * 0.85 + random.range(-0.06...0.06)   // shallow, consistent fan
        let length = random.range(30...46) * scale
        let reach = length * 0.52
        let center = CGPoint(x: tip.x + cos(angle) * reach, y: tip.y + sin(angle) * reach)
        fill(
            leafPath(center: center, length: length, width: length * random.range(0.30...0.40), angle: angle),
            color: colors[index % colors.count].copy(alpha: random.range(0.82...1))!,
            in: context
        )
    }
    // A short terminal leaf closing the fan.
    fill(
        leafPath(center: CGPoint(x: tip.x + cos(along) * 10 * scale, y: tip.y + sin(along) * 10 * scale),
                 length: 34 * scale, width: 12 * scale, angle: along),
        color: colors[0].copy(alpha: 0.95)!,
        in: context
    )
}

private func sapling(
    at base: CGPoint,
    height: CGFloat,
    lean: CGFloat,
    seed: UInt64,
    bark: CGColor,
    leaves: [CGColor],
    in context: CGContext
) {
    var random = Random(seed: seed)

    func stemPoint(_ t: CGFloat) -> CGPoint {
        CGPoint(x: base.x + lean * height * (t * t), y: base.y - height * t)
    }

    // Trunk as a tapering polygon: a real base flare narrowing to a supple tip,
    // instead of a constant-width stroke that reads as a dowel.
    let segs = 20
    let baseHalf = 15.0, tipHalf = 3.0
    var leftEdge: [CGPoint] = []
    var rightEdge: [CGPoint] = []
    for s in 0...segs {
        let t = CGFloat(s) / CGFloat(segs)
        let p = stemPoint(t)
        let half = baseHalf + (tipHalf - baseHalf) * Double(t)
        leftEdge.append(CGPoint(x: p.x - half, y: p.y))
        rightEdge.append(CGPoint(x: p.x + half, y: p.y))
    }
    let trunk = CGMutablePath()
    trunk.move(to: leftEdge[0])
    for p in leftEdge.dropFirst() { trunk.addLine(to: p) }
    for p in rightEdge.reversed() { trunk.addLine(to: p) }
    trunk.closeSubpath()
    fill(trunk, color: bark, in: context)

    // Alternating twigs, each ending in a consistent leaf sprig pointing the way
    // the twig grows — no confetti.
    let twigCount = 5
    for index in 0..<twigCount {
        let t = 0.34 + CGFloat(index) * 0.13
        let node = stemPoint(t)
        let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
        let reach = height * random.range(0.11...0.15) * (1 - t * 0.3)
        let end = CGPoint(x: node.x + side * reach, y: node.y - reach * random.range(0.5...0.8))
        branch(
            from: node,
            via: CGPoint(x: node.x + side * reach * 0.5, y: node.y - reach * 0.28),
            to: end,
            color: bark,
            width: max(5, 11 * (1 - t * 0.4)),
            in: context
        )
        let outward = atan2(end.y - node.y, end.x - node.x)
        leafSprig(at: end, along: outward, count: 4, scale: 0.9,
                  seed: seed + UInt64(index) + 20, colors: leaves, in: context)
    }

    // Terminal shoot: a fuller upward sprig crowning the stem.
    let tip = stemPoint(1)
    leafSprig(at: tip, along: -.pi / 2 + lean, count: 6, scale: 1.05,
              seed: seed + 90, colors: leaves, in: context)
}

private func rock(
    center: CGPoint,
    radiusX: CGFloat,
    radiusY: CGFloat,
    seed: UInt64,
    in context: CGContext
) {
    var random = Random(seed: seed + 7)
    let shadow = smoothBlob(
        center: CGPoint(x: center.x + radiusX * 0.16, y: center.y + radiusY * 0.66),
        radiusX: radiusX * 1.02,
        radiusY: radiusY * 0.34,
        count: 10,
        randomness: 0.16,
        seed: seed + 1
    )
    fill(shadow, color: Palette.deepMoss.copy(alpha: 0.24)!, in: context)

    // Fewer vertices + low randomness give a stone a settled, faceted silhouette
    // rather than a soft amoeba.
    let body = smoothBlob(
        center: center,
        radiusX: radiusX,
        radiusY: radiusY,
        count: 7,
        randomness: 0.17,
        seed: seed
    )
    fill(body, color: Palette.stone, in: context)

    context.saveGState()
    context.addPath(body)
    context.clip()

    // Weight sits in the ground: the lower half darkens.
    let lower = smoothBlob(
        center: CGPoint(x: center.x, y: center.y + radiusY * 0.55),
        radiusX: radiusX * 1.15,
        radiusY: radiusY * 0.8,
        count: 8,
        randomness: 0.12,
        seed: seed + 3
    )
    fill(lower, color: Palette.deepMoss.copy(alpha: 0.20)!, in: context)

    // A broad top-lit plane replaces the old floating crescent line.
    let cap = smoothBlob(
        center: CGPoint(x: center.x - radiusX * 0.14, y: center.y - radiusY * 0.36),
        radiusX: radiusX * 0.74,
        radiusY: radiusY * 0.44,
        count: 9,
        randomness: 0.18,
        seed: seed + 5
    )
    fill(cap, color: CGColor.hex(0xAEBEAF, alpha: 0.65), in: context)

    // Lichen freckles + a couple of grain flecks, scattered on the lit face.
    for _ in 0..<Int(5 + radiusX * 0.06) {
        let a = random.range(0...(2 * .pi))
        let d = sqrt(random.next())
        let px = center.x + cos(a) * radiusX * 0.72 * d
        let py = center.y - radiusY * 0.18 + sin(a) * radiusY * 0.5 * d
        let r = random.range(1.4...3.6)
        context.setFillColor(Palette.lichen.copy(alpha: random.range(0.28...0.6))!)
        context.fillEllipse(in: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2))
    }
    context.restoreGState()
}

private func addStipple(
    count: Int,
    bounds: CGRect,
    color: CGColor,
    radius: ClosedRange<CGFloat>,
    seed: UInt64,
    in context: CGContext
) {
    var random = Random(seed: seed)
    context.setFillColor(color)
    for _ in 0..<count {
        let x = bounds.minX + random.next() * bounds.width
        let y = bounds.minY + random.next() * bounds.height
        let r = random.range(radius)
        context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}

private func drawAtmosphere(in context: CGContext) {
    let full = CGRect(origin: .zero, size: size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let wash = CGGradient(
        colorsSpace: colorSpace,
        colors: [Palette.paper, Palette.sunlight, Palette.mist] as CFArray,
        locations: [0, 0.48, 1]
    )!
    context.drawLinearGradient(wash, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

    // V2 gives the food column a genuinely open pocket of light. Distant
    // detail stops before x=0.30/0.70 rather than ghosting through the copy.
    let clearing = CGGradient(
        colorsSpace: colorSpace,
        colors: [Palette.paper, Palette.sunlight.copy(alpha: 0.58)!, Palette.sunlight.copy(alpha: 0)!] as CFArray,
        locations: [0, 0.60, 1]
    )!
    context.drawRadialGradient(
        clearing,
        startCenter: point(0.5, 0.38),
        startRadius: 0,
        endCenter: point(0.5, 0.40),
        endRadius: size.width * 0.72,
        options: [.drawsAfterEndLocation]
    )

    // Distant forest is deliberately peripheral, leaving one broad visual
    // breath for the status, morsel, and feeding gesture.
    var random = Random(seed: 0xD157A)
    let distantXs: [CGFloat] = [0.025, 0.085, 0.15, 0.22, 0.78, 0.85, 0.92, 0.985]
    for (index, x) in distantXs.enumerated() {
        let top = random.range(0.05...0.26)
        let bottom = random.range(0.56...0.64)
        let lean = random.range(-0.03...0.03)
        let baseHalf = random.range(0.006...0.011)
        let topHalf = baseHalf * random.range(0.28...0.42)   // trunks taper, not bars
        let tint = index.isMultiple(of: 2) ? Palette.sage.copy(alpha: 0.16)! : Palette.beechLight.copy(alpha: 0.12)!

        let trunk = CGMutablePath()
        trunk.move(to: point(x - baseHalf, bottom))
        trunk.addLine(to: point(x + lean - topHalf, top + 0.03))
        trunk.addLine(to: point(x + lean + topHalf, top + 0.03))
        trunk.addLine(to: point(x + baseHalf, bottom))
        trunk.closeSubpath()
        fill(trunk, color: tint, in: context)

        // A soft, faded crown so the far tree stops being a naked pole. Two
        // overlapping wispy masses read as distant foliage the trunk melts into,
        // not a lollipop on a stick.
        for pass in 0..<2 {
            let cx = x + lean + random.range(-0.03...0.03)
            let cy = top - CGFloat(pass) * random.range(0.01...0.03)
            let crown = smoothBlob(
                center: point(cx, cy),
                radiusX: size.width * random.range(0.055...0.085),
                radiusY: size.height * random.range(0.035...0.055),
                count: 13,
                randomness: 0.3,
                seed: 0xD00D + UInt64(index * 2 + pass)
            )
            fill(crown, color: tint.copy(alpha: 0.42)!, in: context)
        }
    }

    // Understory: soft, hazy shrub masses (plain blobs, no vein hatching) so they
    // read as distant foliage rather than mossy boulders.
    var shrubRandom = Random(seed: 0x5417B)
    for (index, spec) in [
        (0.01, 0.58, 0.70), (0.14, 0.61, 0.52), (0.86, 0.61, 0.50),
        (0.99, 0.58, 0.72), (0.22, 0.63, 0.29), (0.78, 0.64, 0.28)
    ].enumerated() {
        let shrub = smoothBlob(
            center: point(spec.0, spec.1),
            radiusX: 150 * spec.2 * shrubRandom.range(0.9...1.2),
            radiusY: 96 * spec.2 * shrubRandom.range(0.9...1.15),
            count: 14,
            randomness: 0.26,
            seed: UInt64(400 + index)
        )
        fill(shrub, color: Palette.sage.copy(alpha: 0.32)!, in: context)
    }

    context.setBlendMode(.multiply)
    addStipple(count: 6_300, bounds: full, color: Palette.ink.copy(alpha: 0.052)!, radius: 0.65...1.9, seed: 0xA11CE, in: context)
    context.setBlendMode(.normal)
}

private func drawTrees(in context: CGContext) {

    // Two different trees now frame the clearing. The oak is warm, broad, and
    // gnarled; the beech is cooler, split, and vertically striated. Their
    // branches stop well outside the central copy column.
    branch(from: point(0.08, 0.30), via: point(0.16, 0.17), to: point(0.23, 0.105), color: Palette.bark, width: 52, in: context)
    branch(from: point(0.12, 0.43), via: point(0.17, 0.35), to: point(0.215, 0.31), color: Palette.bark, width: 28, in: context)
    branch(from: point(0.89, 0.31), via: point(0.84, 0.18), to: point(0.78, 0.115), color: Palette.beech, width: 37, in: context)
    branch(from: point(0.97, 0.22), via: point(0.92, 0.14), to: point(0.865, 0.095), color: Palette.beech, width: 27, in: context)

    fill(leftOakPath(), color: Palette.bark, in: context)
    fill(rightBeechPath(), color: Palette.beech, in: context)
    fill(rightBeechCompanionPath(), color: Palette.deepMoss, in: context)

    // Oak bark: deep furrows that run the full length with the grain, alternating
    // dark cracks and pale ridges. Continuous strokes (no dashes) read as ridged
    // bark instead of a scatter of little cylinders.
    var oakRandom = Random(seed: 0x0A4B4C)
    let oakTop: CGFloat = 0.01, oakBot: CGFloat = 0.63
    for i in 0..<15 {
        let baseX = 0.02 + CGFloat(i) / 14 * 0.13 + oakRandom.range(-0.005...0.005)
        let wander = oakRandom.range(0.005...0.013)
        let phase = oakRandom.range(0...(2 * .pi))
        let waves = oakRandom.range(1.6...3.2)
        let furrow = CGMutablePath()
        let seg = 30
        for s in 0...seg {
            let t = CGFloat(s) / CGFloat(seg)
            // Converge toward the trunk centre near the crown so furrows stay on
            // the wood as the trunk narrows.
            let conv = 0.5 + 0.5 * t
            let x = 0.085 + (baseX - 0.085) * conv + sin(t * waves * .pi + phase) * wander * (0.35 + 0.65 * t)
            let y = oakTop + t * (oakBot - oakTop)
            let pt = point(x, y)
            if s == 0 { furrow.move(to: pt) } else { furrow.addLine(to: pt) }
        }
        let isCrack = i.isMultiple(of: 2)
        let color = isCrack
            ? Palette.deepMoss.copy(alpha: oakRandom.range(0.16...0.30))!
            : Palette.barkLight.copy(alpha: oakRandom.range(0.14...0.26))!
        stroke(furrow, color: color, width: oakRandom.range(4...9), in: context)
    }
    oakKnot(at: point(0.05, 0.30), scale: 1.05, in: context)

    // Beech bark: smooth and pale. Its signature is dark, tapered lenticel
    // "eyebrows" and a few faint blotches — the opposite of the oak's deep grain.
    var beechRandom = Random(seed: 0xBEECA)

    // Soft roundness: a faint darker seam down the shaded left flank of each trunk.
    for spec in [(0.845, 0.615), (0.94, 0.62)] as [(CGFloat, CGFloat)] {
        let seam = CGMutablePath()
        seam.move(to: point(spec.0, -0.02))
        seam.addQuadCurve(to: point(spec.0 + 0.006, spec.1),
                          control: point(spec.0 - 0.004, 0.30))
        stroke(seam, color: Palette.deepMoss.copy(alpha: 0.10)!, width: 26, in: context)
    }

    for _ in 0..<15 {
        let x = beechRandom.range(0.855...1.01)
        let y = beechRandom.range(0.05...0.62)
        let half = beechRandom.range(6...15)
        let lift = beechRandom.range(2...6)
        let mark = CGMutablePath()
        mark.move(to: CGPoint(x: x * size.width - half, y: y * size.height))
        // A shallow upward arc, thin at both ends like a real lenticel.
        mark.addQuadCurve(
            to: CGPoint(x: x * size.width + half, y: y * size.height),
            control: CGPoint(x: x * size.width, y: y * size.height - lift)
        )
        stroke(mark, color: Palette.deepMoss.copy(alpha: beechRandom.range(0.14...0.28))!, width: beechRandom.range(2.5...4.5), in: context)
    }

    // A handful of faint pale blotches to mottle the otherwise clean surface.
    for _ in 0..<5 {
        let center = point(beechRandom.range(0.86...1.0), beechRandom.range(0.06...0.6))
        let blotch = smoothBlob(
            center: center,
            radiusX: beechRandom.range(20...44),
            radiusY: beechRandom.range(12...26),
            count: 8,
            randomness: 0.22,
            seed: UInt64(beechRandom.next() * 99_999)
        )
        fill(blotch, color: Palette.beechLight.copy(alpha: 0.14)!, in: context)
    }

    // Canopies have different silhouettes and leaf languages: round oak masses
    // on the left, layered lance leaves on the right.
    let oakCanopy: [(CGFloat, CGFloat, CGFloat, UInt64, CGColor)] = [
        (-0.055, 0.035, 1.22, 101, Palette.deepMoss),
        (0.095, 0.005, 1.05, 102, Palette.moss),
        (0.18, 0.010, 0.67, 103, Palette.sage),
        (0.015, 0.205, 0.68, 104, Palette.moss)
    ]
    for item in oakCanopy {
        leafCluster(center: point(item.0, item.1), scale: item.2, seed: item.3, color: item.4, in: context)
    }
    leafSpray(
        bounds: CGRect(x: 0, y: 0, width: size.width * 0.20, height: size.height * 0.205),
        count: 54,
        seed: 0x1EAFA,
        colors: [Palette.deepMoss, Palette.moss, Palette.sage],
        slenderness: 1,
        anchor: point(0.075, 0.055),
        in: context
    )

    let beechCanopy: [(CGFloat, CGFloat, CGFloat, UInt64, CGColor)] = [
        (1.055, 0.025, 1.12, 201, Palette.deepMoss),
        (0.925, 0.005, 0.96, 202, Palette.moss),
        (0.84, 0.015, 0.62, 203, Palette.sage),
        (0.985, 0.19, 0.57, 204, Palette.deepMoss)
    ]
    for item in beechCanopy {
        leafCluster(center: point(item.0, item.1), scale: item.2, seed: item.3, color: item.4, in: context)
    }
    leafSpray(
        bounds: CGRect(x: size.width * 0.80, y: 0, width: size.width * 0.20, height: size.height * 0.215),
        count: 62,
        seed: 0x1EAFB,
        colors: [Palette.deepMoss, Palette.moss, Palette.beechLight],
        slenderness: 0.54,
        anchor: point(0.93, 0.05),
        in: context
    )
}

private func drawGround(in context: CGContext) {

    // Ground is painted after the trunks, closing cleanly over the root flares.
    // The oak and beech meet it at visibly different heights.
    let ground = CGMutablePath()
    ground.move(to: point(-0.05, 1.05))
    ground.addLine(to: point(-0.05, 0.635))
    ground.addCurve(to: point(0.24, 0.62), control1: point(0.05, 0.61), control2: point(0.14, 0.65))
    ground.addCurve(to: point(0.50, 0.65), control1: point(0.32, 0.60), control2: point(0.41, 0.65))
    ground.addCurve(to: point(0.76, 0.66), control1: point(0.59, 0.66), control2: point(0.67, 0.64))
    ground.addCurve(to: point(1.05, 0.675), control1: point(0.86, 0.69), control2: point(0.96, 0.64))
    ground.addLine(to: point(1.05, 1.05))
    ground.closeSubpath()
    fill(ground, color: Palette.earth, in: context)

    let meadow = smoothBlob(
        center: point(0.50, 0.815),
        radiusX: size.width * 0.49,
        radiusY: size.height * 0.17,
        count: 18,
        randomness: 0.06,
        seed: 0xBEEFBED
    )
    fill(meadow, color: CGColor.hex(0xC7D884), in: context)

    // A slightly brighter shelf of moss supplies local contrast behind every
    // earned worm length. Kept close to the meadow tone and given an irregular,
    // feathered edge so it reads as sunlit ground, never a puddle or UI halo.
    let wormShelf = smoothBlob(
        center: point(0.50, 0.788),
        radiusX: size.width * 0.375,
        radiusY: size.height * 0.05,
        count: 26,
        randomness: 0.2,
        seed: 0x5E1F
    )
    fill(wormShelf, color: CGColor.hex(0xCCDC90), in: context)
    // Scatter the meadow speckle across it too, so its surface matches the
    // surrounding grass rather than sitting as a clean pool.
    context.saveGState()
    context.addPath(wormShelf)
    context.clip()
    addStipple(
        count: 520,
        bounds: CGRect(x: size.width * 0.1, y: size.height * 0.735, width: size.width * 0.8, height: size.height * 0.11),
        color: Palette.moss.copy(alpha: 0.09)!,
        radius: 0.8...2.2,
        seed: 0x5E1FA,
        in: context
    )
    context.restoreGState()

    // Floor dressing begins only below the root line. Nothing is painted over
    // either trunk, and the shelf itself remains quiet around the name.
    rock(center: point(0.105, 0.815), radiusX: 82, radiusY: 50, seed: 701, in: context)
    rock(center: point(0.875, 0.735), radiusX: 68, radiusY: 42, seed: 702, in: context)
    rock(center: point(0.83, 0.925), radiusX: 114, radiusY: 67, seed: 703, in: context)
    fern(at: point(0.075, 0.88), scale: 0.86, lean: 0.38, color: Palette.deepMoss, seed: 0xFE21, in: context)
    fern(at: point(0.925, 0.88), scale: 0.82, lean: -0.34, color: Palette.moss, seed: 0xFE22, in: context)
    fern(at: point(0.16, 1.01), scale: 0.98, lean: 0.26, color: Palette.moss, seed: 0xFE23, in: context)

    for (index, spec) in [
        (0.055, 0.715, 0.92), (0.16, 0.70, 0.68), (0.84, 0.715, 0.70),
        (0.945, 0.735, 0.94), (0.11, 0.95, 0.74), (0.90, 0.975, 0.72),
        (0.30, 0.955, 0.58), (0.71, 0.965, 0.54)
    ].enumerated() {
        grassTuft(at: point(spec.0, spec.1), scale: spec.2, seed: UInt64(800 + index), color: Palette.moss.copy(alpha: 0.86)!, in: context)
    }

    // Ground pigment avoids the worm shelf so the mascot retains a crisp local
    // silhouette even at its maximum earned length.
    context.saveGState()
    let texturedGround = CGMutablePath()
    texturedGround.addRect(CGRect(x: 0, y: size.height * 0.64, width: size.width, height: size.height * 0.36))
    texturedGround.addEllipse(in: CGRect(x: size.width * 0.105, y: size.height * 0.715, width: size.width * 0.79, height: size.height * 0.145))
    context.addPath(texturedGround)
    context.clip(using: .evenOdd)
    addStipple(
        count: 1_900,
        bounds: CGRect(x: 0, y: size.height * 0.64, width: size.width, height: size.height * 0.36),
        color: Palette.deepMoss.copy(alpha: 0.15)!,
        radius: 1.0...4.5,
        seed: 0x600D,
        in: context
    )
    context.restoreGState()

    addStipple(
        count: 210,
        bounds: CGRect(x: size.width * 0.14, y: size.height * 0.735, width: size.width * 0.72, height: size.height * 0.105),
        color: Palette.moss.copy(alpha: 0.055)!,
        radius: 0.7...1.7,
        seed: 0x5E1F5,
        in: context
    )

}

private func drawForeground(in context: CGContext) {
    // V2 foreground is restrained and side-weighted. It creates depth without
    // crossing the worm, its name, or the tree trunks.
    sapling(
        at: point(0.025, 1.03),
        height: size.height * 0.26,
        lean: 0.17,
        seed: 0x5A91,
        bark: Palette.bark,
        leaves: [Palette.deepMoss, Palette.moss, Palette.sage],
        in: context
    )
    sapling(
        at: point(0.975, 1.03),
        height: size.height * 0.235,
        lean: -0.16,
        seed: 0x5A92,
        bark: Palette.beech,
        leaves: [Palette.deepMoss, Palette.moss, Palette.beechLight],
        in: context
    )

    grassTuft(at: point(0.085, 0.86), scale: 1.04, seed: 901, color: Palette.deepMoss, in: context)
    grassTuft(at: point(0.915, 0.86), scale: 1.00, seed: 902, color: Palette.deepMoss, in: context)
    grassTuft(at: point(0.025, 1.01), scale: 1.30, seed: 903, color: Palette.deepMoss, in: context)
    grassTuft(at: point(0.975, 1.01), scale: 1.34, seed: 904, color: Palette.deepMoss, in: context)

    context.setBlendMode(.multiply)
    addStipple(
        count: 180,
        bounds: CGRect(x: 0, y: size.height * 0.80, width: size.width * 0.16, height: size.height * 0.20),
        color: Palette.ink.copy(alpha: 0.11)!,
        radius: 0.8...2.4,
        seed: 0xF04E,
        in: context
    )
    addStipple(
        count: 180,
        bounds: CGRect(x: size.width * 0.84, y: size.height * 0.80, width: size.width * 0.16, height: size.height * 0.20),
        color: Palette.ink.copy(alpha: 0.11)!,
        radius: 0.8...2.4,
        seed: 0xF04F,
        in: context
    )
}

private func render(_ draw: (CGContext) -> Void, to path: String, opaque: Bool) throws {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "ForestRenderer", code: 1)
    }

    // Core Graphics has a lower-left origin. Flip it so source coordinates read
    // in the same top-down system as SwiftUI.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    if opaque {
        context.setFillColor(Palette.paper)
        context.fill(CGRect(origin: .zero, size: size))
    }
    draw(context)

    guard let image = context.makeImage() else {
        throw NSError(domain: "ForestRenderer", code: 2)
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
        throw NSError(domain: "ForestRenderer", code: 3)
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fputs("usage: swift render_forest_home.swift <atmosphere.png> <trees.png> <ground.png> <foreground.png>\n", stderr)
    exit(2)
}

try render(drawAtmosphere, to: arguments[1], opaque: true)
try render(drawTrees, to: arguments[2], opaque: false)
try render(drawGround, to: arguments[3], opaque: false)
try render(drawForeground, to: arguments[4], opaque: false)
