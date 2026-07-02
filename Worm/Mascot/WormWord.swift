import SwiftUI

/// A continuous, hand-drawn cursive path spelling "worm".
///
/// Authored in a 300×100 design space and laid into the centered region of
/// whatever rect it's given, so the same screen-space path can be both stroked
/// (with `.trim` to animate the writing) and sampled for the pen-tip position
/// via `trimmedPath(...).currentPoint`.
struct WormWord: Shape {
    /// Fraction of the rect's width the word should occupy.
    var widthFraction: CGFloat = 0.66

    func path(in rect: CGRect) -> Path {
        let designW: CGFloat = 300
        let designH: CGFloat = 100

        let targetW = rect.width * widthFraction
        let scale = targetW / designW
        let originX = rect.midX - targetW / 2
        let originY = rect.midY - (designH * scale) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var path = Path()

        // w — two soft valleys
        path.move(to: p(18, 32))
        path.addQuadCurve(to: p(34, 72), control: p(22, 58))
        path.addQuadCurve(to: p(50, 36), control: p(42, 46))
        path.addQuadCurve(to: p(66, 72), control: p(58, 58))
        path.addQuadCurve(to: p(82, 34), control: p(74, 46))

        // o — a full, near-closed loop so it reads as an "o"
        path.addQuadCurve(to: p(112, 31), control: p(98, 25))   // into the top
        path.addQuadCurve(to: p(90, 52), control: p(91, 35))    // down the left
        path.addQuadCurve(to: p(112, 74), control: p(91, 73))   // around the bottom
        path.addQuadCurve(to: p(134, 52), control: p(135, 73))  // up the right
        path.addQuadCurve(to: p(115, 33), control: p(135, 35))  // back to the top, closing

        // r — a TALL, sharp, pointed stem with a small right-flag. Deliberately
        // taller and pointier than the round m humps so it reads as its own
        // letter and not just another arch.
        path.addQuadCurve(to: p(153, 72), control: p(141, 42))  // down to baseline, clearing the o
        path.addLine(to: p(159, 27))                            // tall sharp stem up
        path.addQuadCurve(to: p(172, 40), control: p(165, 29))  // little flag arcing down-right
        path.addLine(to: p(178, 72))                            // sharp downstroke to baseline

        // m — two ROUND humps, clearly shorter than the r's peak
        path.addQuadCurve(to: p(192, 45), control: p(184, 55))
        path.addQuadCurve(to: p(210, 72), control: p(210, 43))
        path.addQuadCurve(to: p(222, 47), control: p(216, 57))
        path.addQuadCurve(to: p(242, 72), control: p(242, 44))
        path.addQuadCurve(to: p(262, 60), control: p(252, 78))

        return path
    }
}

#Preview {
    WormWord()
        .stroke(.black, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        .frame(height: 200)
        .padding()
}
