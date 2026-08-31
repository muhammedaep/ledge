import AppKit
import SwiftUI

/// Hands back the `NSWindow` a SwiftUI view ends up in.
///
/// `NSWindow.didBecomeKeyNotification` is global and carries no way to ask "is
/// this mine", so any view that refreshes on it needs its own window to compare
/// against. Both windows in this app do: the Organize sheet has to tell its own
/// panel coming back from being hidden apart from Settings being brought
/// forward, and the shelf has the same problem for the same reason.
///
/// Reporting from `viewDidMoveToWindow` rather than reading `view.window` after
/// a hop keeps the whole thing on the main actor, with no non-`Sendable` view
/// captured across a boundary.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    final class Reporter: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }

    func makeNSView(context: Context) -> Reporter {
        let view = Reporter()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: Reporter, context: Context) {
        nsView.onWindow = onWindow
    }
}
