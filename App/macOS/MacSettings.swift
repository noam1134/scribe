import KeyboardShortcuts
import ScribeCore
import SwiftUI

/// The Mac's Settings window (spec §9.3: a standard Settings scene, ⌘,).
/// One pane: the sections are few and short.
struct MacSettingsScene: Scene {
    let loader: StoreLoader

    var body: some Scene {
        Settings {
            SettingsView(loader: loader)
                // A fixed window, like most Settings windows; the form scrolls.
                .frame(width: 480, height: 640)
                .onAppear {
                    // Export needs the store, and Settings can open before any window did.
                    if case .loading = loader.state { loader.load() }
                }
        }
    }
}

/// The quick-add shortcut (spec §8, §19), recorded with KeyboardShortcuts:
/// its own dialogs refuse a shortcut the menus use and ask before taking
/// one macOS uses. The note below says when the saved one is taken by macOS.
struct QuickAddHotkeySection: View {
    var body: some View {
        let state = QuickAddHotkey.state
        let note = QuickAddHotkeyNote.settings(shortcut: state.shortcut, isTakenBySystem: state.isTakenBySystem)
        Section {
            KeyboardShortcuts.Recorder("Quick Add", name: .quickAdd) { _ in
                QuickAddHotkey.refreshStatus()
            }
            if note.isWarning {
                Label(note.text, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(note.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !state.isDefault {
                Button("Restore \(QuickAddHotkey.defaultDescription)") {
                    KeyboardShortcuts.reset(.quickAdd)
                    QuickAddHotkey.refreshStatus()
                }
            }
        } header: {
            Text("Keyboard Shortcut")
        }
        .onAppear { QuickAddHotkey.refreshStatus() }
    }
}

#if DEBUG
extension View {
    /// `-uiTesting -showSettings` opens Settings at launch, for screenshots
    /// of a background-launched build.
    func settingsLaunchHook() -> some View {
        modifier(SettingsLaunchHook())
    }
}

private struct SettingsLaunchHook: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.task {
            guard SettingsDemo.showsSettingsAtLaunch else { return }
            try? await Task.sleep(for: .seconds(1))
            openSettings()
        }
    }
}
#endif
