import AppKit
import ScribeCore
import SwiftUI

/// The main window, for code that isn't inside it: the menu bar, the hotkey
/// panel, links. Every path that may open a window goes through `showMain`,
/// which lets one request through at a time (`WindowOpenGate`): a menu bar
/// click sets a link *and* asks for the window, and a requested window
/// isn't on screen yet, so both would otherwise open one.
@MainActor
enum MacWindows {
    /// The id of the main `WindowGroup` in `ScribeApp`.
    static let mainID = "main"

    /// SwiftUI's action for opening a window, handed over by a view that has
    /// it (the menu bar label, always present, and each main window).
    static var openWindow: OpenWindowAction?

    private static var gate = WindowOpenGate()

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            window.identifier?.rawValue.hasPrefix(mainID) == true && (window.isVisible || window.isMiniaturized)
        }
    }

    static var hasMainWindow: Bool { mainWindow != nil }

    /// Activates Scribe and brings its main window forward, or opens one if
    /// they were all closed (once, however many paths ask).
    static func showMain() {
        NSApp.activate()
        guard !bringMainForward() else { return }
        guard let openWindow, gate.requestOpen(now: Date()) else { return }
        openWindow(id: mainID)
    }

    /// Brings an open (or minimized) main window forward; false if none.
    @discardableResult
    static func bringMainForward() -> Bool {
        guard let main = mainWindow else { return false }
        gate.windowAppeared()
        if main.isMiniaturized { main.deminiaturize(nil) }
        main.makeKeyAndOrderFront(nil)
        return true
    }

    /// A main window's root appeared.
    static func mainWindowAppeared(_ openWindow: OpenWindowAction) {
        self.openWindow = openWindow
        gate.windowAppeared()
    }
}
