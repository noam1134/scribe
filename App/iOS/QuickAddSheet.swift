import ScribeCore
import SwiftUI

/// The composer: one line of text with notes under it, live chips for what
/// the parser understood (tap one to undo it), a row of categories to file
/// it into, task/memo toggle, Add (spec §8, §19, §20 — Add waits for a
/// category). Return in the main line saves; focusing Notes grows the sheet.
struct QuickAddSheet: View {
    private enum Field { case title, notes }

    /// Fits the main line, one line of notes, the chips and the categories.
    private static let compact = PresentationDetent.height(252)

    @State private var composer: QuickAddComposer
    @State private var detent = QuickAddSheet.compact
    /// Notes was focused: the sheet may be large from now on. Not before —
    /// with a large detent on offer, the keyboard alone makes the sheet large.
    @State private var canGrow = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @FocusState private var focus: Field?

    init(store: any ItemStore, categoryID: UUID?) {
        let composer = QuickAddComposer(store: store)
        composer.defaultCategoryID = categoryID
        _composer = State(initialValue: composer)
    }

    var body: some View {
        // One parse per keystroke: every derived value comes from this.
        let live = composer.liveParse
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        composer.isMemo.toggle()
                    } label: {
                        kindIcon.foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(composer.isMemo ? "Memo" : "Task")
                    .accessibilityIdentifier("kindToggle")

                    TextField("Add a task or note", text: $composer.text)
                        .font(.title3)
                        .focused($focus, equals: .title)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .layoutDirection(of: composer.text)
                        .accessibilityIdentifier("quickAddField")

                    Button("Add", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(!live.canSave)
                }
                HStack(spacing: 10) {
                    // As wide as the toggle, so Notes lines up with the text.
                    kindIcon.hidden().frame(height: 0)
                    TextField("Notes", text: $composer.notes, axis: .vertical)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...8)
                        .focused($focus, equals: .notes)
                        .layoutDirection(of: composer.notes)
                        .accessibilityIdentifier("quickAddNotes")
                }
            }
            QuickAddChipRow(composer: composer, live: live)
                .buttonStyle(.glass)
            QuickAddCategoryRow(composer: composer, live: live, perform: router.perform)
                .buttonStyle(.glass)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents(canGrow ? [Self.compact, .large] : [Self.compact], selection: $detent)
        .presentationDragIndicator(.visible)
        .onAppear { focus = .title }
        .onChange(of: focus) { _, field in
            guard field == .notes else { return }
            canGrow = true
            withAnimation(.snappy) { detent = .large }
        }
        .saveErrorAlert(router)
    }

    private var kindIcon: some View {
        Image(systemName: composer.isMemo ? "note.text" : "checkmark.circle")
            .font(.title2)
    }

    private func save() {
        router.perform {
            if try composer.save() != nil { dismiss() }
        }
    }
}
