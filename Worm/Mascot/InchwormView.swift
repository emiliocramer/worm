import SwiftUI

/// A self-animating inchworm loader: the standard `Worm` inching in place along
/// a short straight track. Same shape and gait as the splash worm — it just
/// follows a different path. Drop in anywhere a loading indicator is needed.
struct InchwormLoader: View {
    var color: Color = .black
    var eyeColor: Color? = nil
    /// Body thickness as a fraction of the view height.
    var thicknessRatio: CGFloat = 0.14
    /// The base worm to use; `color` and `eyeColor` override its appearance.
    /// Defaults to the calm idle worm so a loader doesn't crawl vigorously.
    var worm: Worm = .calm

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                var w = worm
                w.color = color
                w.eyeColor = eyeColor
                w.thickness = size.height * thicknessRatio
                w.draw(in: context, centerline: Self.track(in: size), time: t)
            }
        }
    }

    /// A flat horizontal track; the worm rests flat and the gentle gait adds the
    /// occasional inch in place.
    private static func track(in size: CGSize) -> [CGPoint] {
        let y = size.height * 0.5
        let x0 = size.width * 0.14
        let x1 = size.width * 0.86
        let steps = 28
        return (0...steps).map { i in
            CGPoint(x: x0 + (x1 - x0) * CGFloat(i) / CGFloat(steps), y: y)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        InchwormLoader()
            .frame(width: 150, height: 80)
            .border(.gray.opacity(0.2))
        InchwormLoader(worm: { var w = Worm.standard; w.color = .blue; return w }())
            .frame(width: 110, height: 60)
    }
    .padding()
}
