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
            QuickAddChipRow(composer: composer, live: live)
                .buttonStyle(.glass)
            QuickAddCategoryRow(composer: composer, live: live, perform: router.perform)
                .buttonStyle(.glass)
        }
        .padding(20)
        .presentationDetents([.height(214)])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
        .saveErrorAlert(router)
    }

    private func save() {
        router.perform {
            if try composer.save() != nil { dismiss() }
        }
    }
}
