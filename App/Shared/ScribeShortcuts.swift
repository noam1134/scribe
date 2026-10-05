import AppIntents

/// Siri phrases (spec §8). English only in v1; what's said or typed after
/// the prompt may be Hebrew. A phrase can't carry free text, so Siri asks
/// "What should I add?".
struct ScribeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddItemIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Add an item to \(.applicationName)",
                "Add a task to \(.applicationName)",
                "New \(.applicationName) item",
            ],
            shortTitle: "Add to Scribe",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: OpenQuickAddIntent(),
            phrases: [
                "Open quick add in \(.applicationName)",
                "Quick add in \(.applicationName)",
            ],
            shortTitle: "Quick Add",
            systemImageName: "square.and.pencil"
        )
    }
}
