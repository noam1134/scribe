import Foundation
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    /// Opens the quick-add panel (spec §8). Settings' recorder changes it.
    static let quickAdd = Self("quickAdd", initial: QuickAddHotkey.defaultShortcut)
}

/// The quick-add shortcut as the menu bar and Settings show it; refreshed
/// whenever it may have changed, so both follow the recorder.
@MainActor
@Observable
final class QuickAddHotkeyState {
    /// "⌃⇧Space"; nil when there is no shortcut.
    fileprivate(set) var shortcut: String?
    fileprivate(set) var isTakenBySystem = false
    fileprivate(set) var isDefault = true
    /// Registered for this run (never in test runs).
    fileprivate(set) var isInstalled = false
    @ObservationIgnored fileprivate var hasRead = false
}

@MainActor
enum QuickAddHotkey {
    /// ⌃⇧Space — amended from spec §8's ⌃⌥Space, which is macOS's "Select
    /// next source in Input menu" on the author's Mac (two input sources).
    nonisolated static let defaultShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .shift])

    static let state = QuickAddHotkeyState()

    /// What the menu bar shows: the shortcut, and whether macOS also uses
    /// it. Nil until installed (never in test runs) or when turned off.
    static var status: (shortcut: String, isTakenBySystem: Bool)? {
        guard state.isInstalled, let shortcut = state.shortcut else { return nil }
        return (shortcut, state.isTakenBySystem)
    }

    /// "⌃⇧Space", for Settings' restore button.
    static var defaultDescription: String { defaultShortcut.description }

    static func install(_ action: @escaping @MainActor () -> Void) {
        replaceOldDefault()
        KeyboardShortcuts.onKeyUp(for: .quickAdd) {
            MacLog.hotkey.info("Quick-add hotkey pressed")
            action()
        }
        state.isInstalled = true
        refreshStatus()
    }

    /// Re-reads the shortcut (at install, when Settings shows it, after the
    /// recorder or Restore changed it) and logs it.
    static func refreshStatus() {
        let shortcut = KeyboardShortcuts.getShortcut(for: .quickAdd)
        let description = shortcut?.description
        let isTakenBySystem = shortcut?.isTakenBySystem ?? false
        let isDefault = shortcut == defaultShortcut
        let changed = !state.hasRead || description != state.shortcut || isTakenBySystem != state.isTakenBySystem
        state.hasRead = true
        if state.shortcut != description { state.shortcut = description }
        if state.isTakenBySystem != isTakenBySystem { state.isTakenBySystem = isTakenBySystem }
        if state.isDefault != isDefault { state.isDefault = isDefault }
        guard changed else { return }
        guard let description else {
            MacLog.hotkey.info("Quick-add hotkey is off")
            return
        }
        MacLog.hotkey.info("Quick-add hotkey: \(description, privacy: .public)")
        if isTakenBySystem {
            MacLog.hotkey.warning("Quick-add hotkey is also a system shortcut; macOS may get it first")
        }
    }

    /// KeyboardShortcuts stores the initial shortcut on first use, so a
    /// build that shipped ⌃⌥Space would keep it. Nobody could have chosen it
    /// on purpose before the recorder (Phase 6): replace it, once.
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
