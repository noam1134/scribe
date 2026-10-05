import ScribeCore
import SwiftUI

/// The composer: one line of text, live chips for what the parser
/// understood (tap one to undo it), a row of categories to file it into,
/// task/memo toggle, Add (spec §8, §19 — Add waits for a category).
struct QuickAddSheet: View {
    @State private var composer: QuickAddComposer
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @FocusState private var focused: Bool

    init(store: any ItemStore, categoryID: UUID?) {
        let composer = QuickAddComposer(store: store)
        composer.defaultCategoryID = categoryID
        _composer = State(initialValue: composer)
    }

    var body: some View {
        // One parse per keystroke: every derived value comes from this.
        let live = composer.liveParse
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    composer.isMemo.toggle()
                } label: {
                    Image(systemName: composer.isMemo ? "note.text" : "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(composer.isMemo ? "Memo" : "Task")
                .accessibilityIdentifier("kindToggle")

                TextField("Add a task or note", text: $composer.text)
                    .font(.title3)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .layoutDirection(of: composer.text)
                    .accessibilityIdentifier("quickAddField")

                Button("Add", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(!live.canSave)
            }
            chips(live)
            categoryRow(live)
        }
        .padding(20)
        .presentationDetents([.height(214)])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
        .saveErrorAlert(router)
    }

    @ViewBuilder private func chips(_ live: QuickAddComposer.LiveParse) -> some View {
        if !live.chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        ForEach(live.chips) { chip in
                            Button { composer.dismiss(chip) } label: {
                                Label(chip.label, systemImage: icon(for: chip.kind))
                            }
                            .buttonStyle(.glass)
                            .accessibilityHint("Removes this and keeps the text in the title")
                        }
                    }
                }
            }
        } else {
            Text("Try \u{201C}call mom tomorrow 9am #family\u{201D}")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    /// Where the item goes. One tap picks; a typed `#tag` picks for you; a
    /// typed unknown `#name` offers to create it. No Inbox here (spec §19).
    @ViewBuilder private func categoryRow(_ live: QuickAddComposer.LiveParse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(live.categories) { category in
                        let picked = category.id == live.categoryID
                        Button {
                            composer.select(category.id)
                        } label: {
                            Label {
                                Text(category.displayName)
                                    .fontWeight(picked ? .semibold : .regular)
                            } icon: {
                                Image(systemName: picked ? "checkmark.circle.fill" : "circle.fill")
                                    .foregroundStyle(category.color)
                            }
                        }
                        .buttonStyle(.glass)
                        .accessibilityAddTraits(picked ? .isSelected : [])
                        .accessibilityIdentifier("pickCategory-\(category.name)")
                    }
                    if let name = live.unknownCategoryName {
                        Button("New category \u{201C}\(name)\u{201D}", systemImage: "plus") {
                            router.perform { try composer.createUnknownCategory() }
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("newCategoryChip")
                    }
                }
            }
            .scrollClipDisabled()
            if live.categories.isEmpty && live.unknownCategoryName == nil {
                hint("Type #name to create a category")
            } else if live.draft.isValid && live.categoryID == nil {
                hint("Pick a category")
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("categoryHint")
    }

    private func icon(for kind: TokenKind) -> String {
        switch kind {
        case .category: "folder"
        case .kind: "note.text"
        case .date: "calendar"
        case .time: "clock"
        }
    }

    private func save() {
        router.perform {
            if try composer.save() != nil { dismiss() }
        }
    }
}
