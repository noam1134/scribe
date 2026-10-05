import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⌃⌥Space opens the quick-add panel (spec §8). The recorder that
    /// changes it is Phase 6's Settings.
    static let quickAdd = Self("quickAdd", initial: .init(.space, modifiers: [.control, .option]))
}

enum QuickAddHotkey {
    @MainActor
    static func install(_ action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .quickAdd) {
            MacLog.hotkey.info("Quick-add hotkey pressed")
            action()
        }
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .quickAdd) else {
            MacLog.hotkey.info("Quick-add hotkey is off")
            return
        }
        MacLog.hotkey.info("Quick-add hotkey: \(shortcut.description, privacy: .public)")
        if shortcut.isTakenBySystem {
            // ⌃⌥Space is also macOS's "Select next source in Input menu".
            MacLog.hotkey.warning("Quick-add hotkey is also a system shortcut; macOS may get it first")
        }
    }
}
