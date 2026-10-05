import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens the quick-add panel (spec §8). The recorder that changes it is
    /// Phase 6's Settings.
    static let quickAdd = Self("quickAdd", initial: QuickAddHotkey.defaultShortcut)
}

@MainActor
enum QuickAddHotkey {
    /// ⌃⇧Space — amended from spec §8's ⌃⌥Space, which is macOS's "Select
    /// next source in Input menu" on the author's Mac (two input sources).
    nonisolated static let defaultShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .shift])

    /// What the menu bar shows: the shortcut, and whether macOS also uses
    /// it. Nil until installed (never in test runs) or when turned off.
    static private(set) var status: (shortcut: String, isTakenBySystem: Bool)?

    static func install(_ action: @escaping @MainActor () -> Void) {
        replaceOldDefault()
        KeyboardShortcuts.onKeyUp(for: .quickAdd) {
            MacLog.hotkey.info("Quick-add hotkey pressed")
            action()
        }
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .quickAdd) else {
            MacLog.hotkey.info("Quick-add hotkey is off")
            return
        }
        status = (shortcut.description, shortcut.isTakenBySystem)
        MacLog.hotkey.info("Quick-add hotkey: \(shortcut.description, privacy: .public)")
        if shortcut.isTakenBySystem {
            MacLog.hotkey.warning("Quick-add hotkey is also a system shortcut; macOS may get it first")
        }
    }

    /// KeyboardShortcuts stores the initial shortcut on first use, so a
    /// build that shipped ⌃⌥Space would keep it. Nobody could have chosen it
    /// on purpose yet (no recorder before Phase 6): replace it, once.
    private static func replaceOldDefault() {
        let key = "QuickAddHotkeyReplacedControlOptionSpace"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        if KeyboardShortcuts.getShortcut(for: .quickAdd) == KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .option]) {
            KeyboardShortcuts.setShortcut(defaultShortcut, for: .quickAdd)
            MacLog.hotkey.info("Quick-add hotkey moved from ⌃⌥Space to the new default")
        }
    }
}
