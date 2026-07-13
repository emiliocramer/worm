import SwiftUI
import UIKit

/// App-wide input rule: tapping anywhere outside an active text input dismisses
/// the keyboard. Keep this installed once at the root so every current and
/// future input inherits the same behavior without per-screen tap plumbing.
struct KeyboardDismissalModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                KeyboardDismissInstaller()
                    .frame(width: 0, height: 0)
            )
    }
}

extension View {
    func dismissKeyboardOnOutsideTap() -> some View {
        modifier(KeyboardDismissalModifier())
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateUIView(_ uiView: WindowProbeView, context: Context) {
        context.coordinator.install(in: uiView.window)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var tapRecognizer: UITapGestureRecognizer?

        func install(in window: UIWindow?) {
            guard let window else { return }
            guard installedWindow !== window else { return }

            if let installedWindow, let tapRecognizer {
                installedWindow.removeGestureRecognizer(tapRecognizer)
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)

            installedWindow = window
            tapRecognizer = tap
        }

        deinit {
            if let installedWindow, let tapRecognizer {
                installedWindow.removeGestureRecognizer(tapRecognizer)
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            installedWindow?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = touch.view else { return true }
            return !view.hasTextInputAncestor
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private final class WindowProbeView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}

private extension UIView {
    var hasTextInputAncestor: Bool {
        var view: UIView? = self
        while let current = view {
            if current is UITextField || current is UITextView {
                return true
            }
            view = current.superview
        }
        return false
    }
}
