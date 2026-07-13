import SwiftUI

/// Renders a worm body along a centerline polyline: a continuous rounded tube
/// with an optional eye. Reusable by anything that can produce a centerline
/// (the splash, the loader, …) so the little guy looks consistent everywhere.
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

        // Uniform body width with naturally rounded stroke caps, no bead stamps.
        func radius(_ u: CGFloat) -> CGFloat {
            maxR
        }

        var body = Path()
        body.move(to: points[0])
        for point in points.dropFirst() {
            body.addLine(to: point)
        }
        context.stroke(
            body,
            with: .color(color),
            style: StrokeStyle(lineWidth: maxWidth, lineCap: .round, lineJoin: .round)
        )

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
