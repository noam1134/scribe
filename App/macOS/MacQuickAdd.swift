import ScribeCore
import SwiftUI

/// The Mac composer — task/memo toggle, the field, and the parse and
/// category chip rows — shared by the window, the menu bar and the hotkey
/// panel (spec §8, §19). Return adds. Chips are bordered: each surface
/// draws the composer on glass, and glass never sits on glass (spec §9.1).
struct MacComposer<Focus: Hashable>: View {
    let store: any ItemStore
    @Bindable var composer: QuickAddComposer
    var focus: FocusState<Focus?>.Binding
    let focusValue: Focus
    /// Whether the chip rows show (the window shows them while composing).
    var showsChips = true
    var font: Font = .body
    /// Runs a store write and shows a refusal.
    let perform: @MainActor (() throws -> Void) -> Void
    /// Called after an add with "Added to 🇹🇭 Thailand".
    let added: (String) -> Void

    var body: some View {
        // One parse per keystroke: every derived value comes from this.
        let live = composer.liveParse
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    composer.isMemo.toggle()
                } label: {
                    Image(systemName: composer.isMemo ? "note.text" : "checkmark.circle")
                        .font(font)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help(composer.isMemo ? "Memo (click for a task)" : "Task (click for a memo)")
                .accessibilityLabel(composer.isMemo ? "Memo" : "Task")

                TextField("Add a task or note", text: $composer.text)
                    .textFieldStyle(.plain)
                    .font(font)
                    .focused(focus, equals: focusValue)
                    .onSubmit(save)
                    .layoutDirection(of: composer.text)
            }
            if showsChips {
                QuickAddChipRow(composer: composer, live: live)
                QuickAddCategoryRow(composer: composer, live: live, perform: perform)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    private func save() {
        perform {
            guard let id = try composer.save(), let item = store.item(id) else { return }
            let category = store.categories.first { $0.id == item.categoryID }
            added("Added to \(category?.displayName ?? "Inbox")")
        }
    }
}

/// The window's quick-add: a glass field at the bottom of the list that
/// opens into the full composer while it has focus or text. ⌘N focuses it;
/// the category on screen is preselected (spec §19). Return adds and keeps
/// the field ready for the next one; Esc clears it, then leaves it.
struct MacQuickAddBar: View {
    let store: any ItemStore
    var focus: FocusState<MacRouter.Focus?>.Binding

    @Environment(MacRouter.self) private var router
    @State private var composer: QuickAddComposer
    @State private var confirmation: String?

    init(store: any ItemStore, focus: FocusState<MacRouter.Focus?>.Binding) {
        self.store = store
        self.focus = focus
        _composer = State(initialValue: QuickAddComposer(store: store))
    }

    var body: some View {
        let isOpen = focus.wrappedValue == .quickAdd || !composer.text.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            MacComposer(
                store: store,
                composer: composer,
                focus: focus,
                focusValue: .quickAdd,
                showsChips: isOpen,
                perform: router.perform
            ) { confirmation = $0 }
            if let confirmation {
                Text(confirmation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("addedConfirmation")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // The chip rows scroll unclipped (spec §9.1): clip them to the box
        // instead, so the last chip slides under its edge. Opening isn't
        // animated: the window lays the taller bar out at once while an
        // animated glass shape lagged behind it, leaving the chips outside.
        .clipShape(.rect(cornerRadius: 20))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .onChange(of: router.sidebar, initial: true) { _, entry in
            composer.defaultCategoryID = entry.categoryID
        }
        .onChange(of: composer.text) { _, text in
            if !text.isEmpty { confirmation = nil }
        }
        .onChange(of: isOpen) { _, open in
            if !open { confirmation = nil }
        }
        .onExitCommand {
            if composer.text.isEmpty {
                focus.wrappedValue = .list
            } else {
                composer.reset()
            }
        }
    }
}
