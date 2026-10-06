import ScribeCore
import SwiftUI

/// The composer: one line of text with notes under it, live chips for what
/// the parser understood (tap one to undo it), a row of categories to file
/// it into, task/memo toggle, Add (spec §8, §19, §20 — Add waits for a
/// category). Return in the main line saves. The sheet is as tall as its
/// content — it grows a line at a time as notes are typed — up to
/// `maxHeight`, past which it scrolls.
struct QuickAddSheet: View {
    private enum Field { case title, notes }

    let maxHeight: CGFloat

    @State private var composer: QuickAddComposer
    /// Measured; starts near one line of notes.
    @State private var contentHeight: CGFloat = 250
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @FocusState private var focus: Field?

    init(store: any ItemStore, categoryID: UUID?, maxHeight: CGFloat) {
        let composer = QuickAddComposer(store: store)
        composer.defaultCategoryID = categoryID
        _composer = State(initialValue: composer)
        self.maxHeight = maxHeight
    }

    var body: some View {
        // One parse per keystroke: every derived value comes from this.
        let live = composer.liveParse
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button {
                            composer.isMemo.toggle()
                        } label: {
                            kindIcon.foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .keepsKeyboardOnTap()
                        .accessibilityLabel(composer.isMemo ? "Memo" : "Task")
                        .accessibilityIdentifier("kindToggle")

                        TextField("Add a task or note", text: $composer.text)
                            .font(.body)
                            .focused($focus, equals: .title)
                            .submitLabel(.done)
                            .onSubmit(save)
                            .layoutDirection(of: composer.text)
                            .accessibilityIdentifier("quickAddField")

                        addButton(enabled: live.canSave)
                    }
                    // Between invisible copies of the toggle and Add, so the
                    // notes start and end where the title does (either
                    // direction).
                    HStack(spacing: 10) {
                        kindIcon.hidden().frame(height: 0).accessibilityHidden(true)
                        TextField("Notes", text: $composer.notes, axis: .vertical)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1...8)
                            .focused($focus, equals: .notes)
                            .layoutDirection(of: composer.notes)
                            .accessibilityIdentifier("quickAddNotes")
                        addButton(enabled: true).hidden().frame(height: 0).accessibilityHidden(true)
                    }
                }
                QuickAddChipRow(composer: composer, live: live)
                    .buttonStyle(.glass)
                    // The example line is text: a tap there still closes the keyboard.
                    .keepsKeyboardOnTap(!live.chips.isEmpty)
                QuickAddCategoryRow(composer: composer, live: live, perform: router.perform)
                    .buttonStyle(.glass)
                    .keepsKeyboardOnTap()
            }
            // Small chips: the sheet stays a compact strip above the keyboard.
            .font(.subheadline)
            .controlSize(.small)
            .padding(16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.never)
        .presentationDetents([.height(min(contentHeight, maxHeight))])
        .presentationDragIndicator(.visible)
        .onAppear { focus = .title }
        .suggestsCategory(for: composer, request: live.suggestionRequest)
        .saveErrorAlert(router)
    }

    private var kindIcon: some View {
        Image(systemName: composer.isMemo ? "note.text" : "checkmark.circle")
            .font(.title3)
    }

    private func addButton(enabled: Bool) -> some View {
        Button("Add", action: save)
            .buttonStyle(.glassProminent)
            .disabled(!enabled)
    }

    private func save() {
        router.perform {
            if try composer.save() != nil { dismiss() }
        }
    }
}
