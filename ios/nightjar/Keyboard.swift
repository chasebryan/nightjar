import SwiftUI
import UIKit

/// One way to fold the keyboard, everywhere:
/// swipe down, anywhere, and it goes away. A
/// single swipe recognizer rides on the window
/// itself, so every tab, sheet and form in the
/// house inherits it — no screen has to
/// remember to offer it, and no screen can
/// forget. It only observes (it never cancels
/// a touch, and it recognizes alongside every
/// other gesture), and when no keyboard is up
/// its one act — resign the first responder —
/// is a harmless no-op.
struct KeyboardSwipeInstaller: UIViewRepresentable {
    func makeUIView(context: Context)
        -> KeyboardSwipeView {
        KeyboardSwipeView()
    }

    func updateUIView(_ uiView: KeyboardSwipeView,
                      context: Context) {}
}

final class KeyboardSwipeView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            KeyboardSwipe.install(in: window)
        }
    }
}

enum KeyboardSwipe {
    static let name = "nightjar.keyboardSwipe"
    private static let dismisser = KeyboardDismisser()

    static func install(in window: UIWindow) {
        let already = window.gestureRecognizers?
            .contains { $0.name == name } ?? false
        guard !already else { return }
        let swipe = UISwipeGestureRecognizer(
            target: dismisser,
            action: #selector(
                KeyboardDismisser.handle(_:)))
        swipe.name = name
        swipe.direction = .down
        swipe.cancelsTouchesInView = false
        swipe.delegate = dismisser
        window.addGestureRecognizer(swipe)
    }
}

final class KeyboardDismisser: NSObject,
    UIGestureRecognizerDelegate {

    @objc func handle(
        _ recognizer: UISwipeGestureRecognizer) {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            other: UIGestureRecognizer) -> Bool {
        true
    }
}
