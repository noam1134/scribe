import ScribeCore
import SwiftUI

/// Menu-bar commands for the key window (spec §9.3). Space and Return are
/// handled by the list itself: as menu shortcuts they would also swallow
/// those keys in text fields. ⌘Z / ⇧⌘Z are the standard Edit › Undo / Redo,
/// fed by `StoreUndo`.
struct MacCommands: Commands {
    @FocusedValue(MacRouter.self) private var router

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Item") { router?.run(.newItem) }
                .keyboardShortcut("n")
                .disabled(router == nil)
        }
        // Before the Edit menu's Find items, which are disabled outside text
        // and would swallow ⌘F.
        CommandGroup(before: .textEditing) {
            Button("Search") { router?.run(.find) }
                .keyboardShortcut("f")
                .disabled(router == nil)
            Divider()
        }
        CommandMenu("Item") {
            Button("Edit Item") { router?.run(.edit) }
                .disabled(!(router?.canRun(.edit) ?? false))
            Button(doneTitle) { router?.run(.toggleDone) }
                .disabled(!(router?.canRun(.toggleDone) ?? false))
            Divider()
            // Never disabled: a disabled menu shortcut still swallows ⌘⌫, which
            // text fields need. The command hands it back to them.
            Button("Delete Item") { MacRouter.deleteCommand(router) }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        CommandMenu("Go") {
            Button("Upcoming") { router?.run(.jump(0)) }
                .keyboardShortcut("0")
                .disabled(router == nil)
            if let categories = router?.store.categories, !categories.isEmpty {
                Divider()
                ForEach(Array(categories.prefix(9).enumerated()), id: \.element.id) { index, category in
                    Button(category.displayName) { router?.run(.jump(index + 1)) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
        }
    }

    private var doneTitle: String {
        let item = router?.selectedItemID.flatMap { router?.store.item($0) }
        return item?.isDone == true ? "Mark as Not Done" : "Mark as Done"
    }
}
