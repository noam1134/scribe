import SwiftUI
import UIKit

extension View {
    /// A tap anywhere outside a text field closes the keyboard (spec §20).
    /// The tap still does what it would have done — buttons and chips work
    /// on the first tap — and a tap on another field just moves the focus.
    func closesKeyboardOnTapOutside() -> some View {
        background(WindowTapHook())
    }
}

/// Puts one `KeyboardDismissTap` on the window this view lands in; sheets
/// are presented in the same window.
private struct WindowTapHook: UIViewRepresentable {
    func makeUIView(context: Context) -> HookView {
        let view = HookView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HookView, context: Context) {}

    final class HookView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is KeyboardDismissTap }) else { return }
            window.addGestureRecognizer(KeyboardDismissTap())
        }
    }
}

/// Recognizes alongside every other gesture and never cancels or delays
/// touches, so the tapped control gets its tap as usual.
private final class KeyboardDismissTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(tapped))
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        delegate = self
    }

    @objc private func tapped() {
        view?.endEditing(true)
    }

    /// A touch in a text field or text view is that field's: no flicker.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
