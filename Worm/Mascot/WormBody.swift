import SwiftUI

/// Renders a worm body along a centerline polyline: a pointy tail that swells
/// into a belly and rounds off into a head, with an optional eye. Reusable by
/// anything that can produce a centerline (the splash, the loader, …) so the
/// little guy looks consistent everywhere.
enum WormBody {
    static func draw(
        _ context: GraphicsContext,
        centerline points: [CGPoint],
        maxWidth: CGFloat,
        color: Color = .black,
        eyeColor: Color? = nil
    ) {
        let n = points.count
        guard n >= 2 else { return }

        let maxR = maxWidth / 2

        // A thin worm of constant width: uniform body with naturally rounded ends
        // (the end stamps are full circles), no taper and no bulbous head.
        func radius(_ u: CGFloat) -> CGFloat {
            maxR
        }

        // Stamp overlapping circles along the centerline and union them with a
        // single fill. This stays perfectly round and unbroken even where the
        // path turns sharply (e.g. the "r"), unlike an offset ribbon.
        var blob = Path()
        func stamp(_ c: CGPoint, _ r: CGFloat) {
            blob.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }

        for i in 0..<n {
            let u = CGFloat(i) / CGFloat(n - 1)
            let r = radius(u)
            stamp(points[i], r)

            // If samples are sparse relative to the radius, add a midpoint stamp
            // so the tube never gaps.
            if i < n - 1 {
                let next = points[i + 1]
                let d = hypot(next.x - points[i].x, next.y - points[i].y)
                if d > r * 0.6 {
                    let uMid = (CGFloat(i) + 0.5) / CGFloat(n - 1)
                    stamp(CGPoint(x: (points[i].x + next.x) / 2, y: (points[i].y + next.y) / 2), radius(uMid))
                }
            }
        }

        context.fill(blob, with: .color(color))

        // Eye — a small hole near the top of the tapered head, facing travel.
        if let eyeColor {
            let head = points[n - 1]
            let rHead = radius(1)
            let back = points[max(0, n - 3)]
            let dx = head.x - back.x
            let dy = head.y - back.y
            let len = max(0.0001, hypot(dx, dy))
            let fx = dx / len, fy = dy / len   // forward
            let ux = fy, uy = -fx              // "up" relative to travel
            let center = CGPoint(x: head.x - fx * rHead * 0.15 + ux * rHead * 0.3,
                                 y: head.y - fy * rHead * 0.15 + uy * rHead * 0.3)
            let er = rHead * 0.38
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - er, y: center.y - er, width: er * 2, height: er * 2)),
                with: .color(eyeColor)
            )
        }
    }
}

private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
