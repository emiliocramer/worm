import SwiftUI

/// One source-sized plate from the forest artwork. Keeping every plate on the
/// same canvas makes the animated masks line up exactly with the final scene.
struct ForestHomeScene: View {
    enum Layer {
        case atmosphere
        case trees
        case ground
        case foreground

        var assetName: String {
            switch self {
            case .atmosphere: "ForestHomeBackground"
            case .trees: "ForestHomeTrees"
            case .ground: "ForestHomeGround"
            case .foreground: "ForestHomeForeground"
            }
        }
    }

    let layer: Layer

    var body: some View {
        Image(layer.assetName)
            .resizable(resizingMode: .stretch)
            .interpolation(.high)
            .antialiased(true)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Resolves the habitat in authored depth order. Every plate keeps its final
/// geometry throughout; this is a layered dissolve, never a growth effect.
struct ForestHomeBackdrop: View {
    let buildProgress: CGFloat

    var body: some View {
        let atmosphere = forestPhase(buildProgress, from: 0, to: 0.27)
        let ground = forestPhase(buildProgress, from: 0.14, to: 0.52)
        let leftTree = forestPhase(buildProgress, from: 0.28, to: 0.72)
        let rightTree = forestPhase(buildProgress, from: 0.36, to: 0.80)

        ZStack {
            ForestHomeScene(layer: .atmosphere)
                .opacity(atmosphere)
                .blur(radius: 2.5 * (1 - atmosphere))

            ForestHomeScene(layer: .trees)
                .mask(ForestTreeSideMask(side: .left))
                .offset(x: -9 * (1 - leftTree))
                .blur(radius: 1.4 * (1 - leftTree))
                .opacity(leftTree)

            ForestHomeScene(layer: .trees)
                .mask(ForestTreeSideMask(side: .right))
                .offset(x: 9 * (1 - rightTree))
                .blur(radius: 1.4 * (1 - rightTree))
                .opacity(rightTree)

            ForestHomeScene(layer: .ground)
                .blur(radius: 1.8 * (1 - ground))
                .opacity(ground)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Near detail resolves last without changing scale or position.
struct ForestHomeForeground: View {
    let buildProgress: CGFloat

    var body: some View {
        let foreground = forestPhase(buildProgress, from: 0.64, to: 1)
        ForestHomeScene(layer: .foreground)
            .blur(radius: 1.2 * (1 - foreground))
            .opacity(foreground)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum ForestSide {
    case left
    case right
}

private struct ForestTreeSideMask: Shape {
    let side: ForestSide

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(
            x: side == .left ? 0 : rect.width * 0.49,
            y: 0,
            width: rect.width * 0.51,
            height: rect.height
        ))
        return path
    }
}

private func forestPhase(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
    let x = min(max((value - start) / (end - start), 0), 1)
    return x * x * (3 - 2 * x)
}
