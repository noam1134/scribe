import AppIntents

struct ProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddProbeNoteIntent(),
            phrases: ["Add probe note in \(.applicationName)"],
            shortTitle: "Add Probe Note",
            systemImageName: "plus.circle"
        )
    }
}
