import ScribeCore
import SwiftUI

/// The composer: one line of text, live chips for what the parser
/// understood (tap one to undo it), task/memo toggle, Add (spec §8).
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
        }
        .padding(20)
        .presentationDetents([.height(150)])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
        .saveErrorAlert(router)
    }

    @ViewBuilder private func chips(_ live: QuickAddComposer.LiveParse) -> some View {
        if !live.chips.isEmpty || live.unknownCategoryName != nil {
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
                        if let name = live.unknownCategoryName {
                            Button("New category \u{201C}\(name)\u{201D}", systemImage: "plus") {
                                router.perform { try composer.createUnknownCategory() }
                            }
                            .buttonStyle(.glass)
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
