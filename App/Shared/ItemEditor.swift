import ScribeCore
import SwiftUI

/// A tapped row's inline editor (spec §9.2): title, notes, and a row of
/// glass chips for date, category and kind. Text saves on Return (which also
/// closes the editor), when the editor goes away and when the app leaves the
/// foreground; chips save immediately. Only the text fields the user changed
/// are written (`ItemTextDraft`). On the Mac the title is focused when the
/// editor opens and Esc closes it (spec §9.3).
struct ItemEditor: View {
    /// Writes an edit to the item; the name is for Edit › Undo.
    typealias Save = @MainActor (_ id: UUID, _ actionName: String, _ edit: (inout ItemEdit) -> Void) throws -> Void

    let store: any ItemStore
    let item: ItemSnapshot
    let categories: [CategorySnapshot]
    /// Runs a store write and shows a refusal (each platform's alert).
    let perform: @MainActor (() throws -> Void) -> Void
    /// nil writes straight to the store (the iPhone); the Mac makes every
    /// write undoable.
    let save: Save?
    /// Whether to put the caret in the title now; asked when the editor
    /// appears. Once per opening, so a rebuilt editor doesn't take focus.
    let takeTitleFocus: (@MainActor () -> Bool)?
    let close: () -> Void

    private enum InlinePicker { case date, time }

    @Environment(\.scenePhase) private var scenePhase
    @State private var text: ItemTextDraft
    @State private var picker: InlinePicker?
    #if os(macOS)
    @FocusState private var titleFocused: Bool
    #endif

    private let calendar = Calendar.autoupdatingCurrent
    private var today: LocalDay { LocalDay(Date(), calendar: calendar) }

    init(
        store: any ItemStore,
        item: ItemSnapshot,
        categories: [CategorySnapshot],
        perform: @escaping @MainActor (() throws -> Void) -> Void,
        save: Save? = nil,
        takeTitleFocus: (@MainActor () -> Bool)? = nil,
        close: @escaping () -> Void
    ) {
        self.store = store
        self.item = item
        self.categories = categories
        self.perform = perform
        self.save = save
        self.takeTitleFocus = takeTitleFocus
        self.close = close
        _text = State(initialValue: ItemTextDraft(title: item.title, notes: item.body))
    }

    private var titleField: some View {
        let field = TextField("Title", text: $text.title)
            .submitLabel(.done)
            .onSubmit {
                finish()
                close()
            }
            .accessibilityIdentifier("titleField")
        #if os(macOS)
        return field.focused($titleFocused)
        #else
        // Only as wide as the title, so a tap beside a short title reaches
        // the row (which closes the editor) instead of starting to edit.
        return Text(text.title.isEmpty ? "Title" : text.title + "  ")
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) { field }
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleField
                // The row's title style: opening the editor swaps one for the
                // other without the title changing.
                .font(.body)
                .layoutDirection(of: text.title)
            TextField("Notes", text: $text.notes, axis: .vertical)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1...6)
                .layoutDirection(of: text.notes)
                .accessibilityIdentifier("notesField")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dateChip
                    categoryChip
                    kindChip
                }
                .font(.subheadline)
                .controlSize(.small)
            }
            .scrollClipDisabled() // clipping draws a grey band behind the glass chips
            switch picker {
            case .date:
                DatePicker("Date", selection: dayBinding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            case .time:
                timePicker
            case nil:
                EmptyView()
            }
        }
        .onDisappear(perform: finish)
        .onChange(of: scenePhase) { _, phase in
            // The app may be ended in the background: keep what was typed.
            if phase != .active { saveText() }
        }
        #if os(macOS)
        // After this pass, not inside it: the row is still being built by
        // the list's table view.
        .task {
            if takeTitleFocus?() == true { titleFocused = true }
        }
        .onExitCommand {
            finish()
            close()
        }
        #endif
    }

    @ViewBuilder private var timePicker: some View {
        #if os(iOS)
        DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        #else
        DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    // MARK: Chips

    private var dateChip: some View {
        Menu {
            ForEach(DatePreset.allCases, id: \.self) { preset in
                Button(preset.title) { setDue(preset.applied(to: item.due, today: today, calendar: calendar)) }
            }
            Button("Pick a Date…", systemImage: "calendar") { show(.date) }
            if let due = item.due {
                Button(due.minute == nil ? "Add Time…" : "Change Time…", systemImage: "clock") { show(.time) }
                if due.minute != nil {
                    Button("Remove Time") { setDue(DueDate(day: due.day)) }
                }
                Button("Remove Date", role: .destructive) {
                    picker = nil
                    setDue(nil)
                }
            }
        } label: {
            Label(item.due.map { DueLabels().due($0, today: today) } ?? "No Date", systemImage: "calendar")
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("dateChip")
    }

    private var categoryChip: some View {
        let category = item.categoryID.flatMap { id in categories.first { $0.id == id } }
        // No Inbox to move into (spec §19); an item already there shows
        // "Inbox" until it's given a category.
        return Menu {
            ForEach(categories) { option in
                Button {
                    update("Move to \u{201C}\(option.name)\u{201D}") { $0.categoryID = option.id }
                } label: {
                    if option.id == item.categoryID {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Label {
                Text(category?.displayName ?? "Inbox")
            } icon: {
                Image(systemName: category == nil ? "tray" : "circle.fill")
                    .foregroundStyle(category?.color ?? .secondary)
            }
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("categoryChip")
    }

    private var kindChip: some View {
        Button(item.kind == .task ? "Task" : "Memo",
               systemImage: item.kind == .task ? "checkmark.circle" : "note.text") {
            update(item.kind == .task ? "Make Memo" : "Make Task") { $0.kind = item.kind == .task ? .memo : .task }
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("kindChip")
    }

    // MARK: Bindings

    /// The inline calendar edits the day and keeps the time.
    private var dayBinding: Binding<Date> {
        Binding(
            get: { (item.due?.day ?? today).date(calendar: calendar) },
            set: { date in setDue(DueDate(day: LocalDay(date, calendar: calendar), minute: item.due?.minute)) }
        )
    }

    /// The inline wheel edits the time and keeps the day.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { (item.due?.day ?? today).date(atMinute: item.due?.minute ?? 9 * 60, calendar: calendar) },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                setDue(DueDate(day: item.due?.day ?? today, minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
            }
        )
    }

    // MARK: Saving

    private func show(_ inline: InlinePicker) {
        withAnimation(.snappy) { picker = picker == inline ? nil : inline }
    }

    /// Return, or the editor going away. An empty title is never saved
    /// (spec §13), so the field shows the last saved one again.
    private func finish() {
        saveText()
        text.restoreEmptyTitle()
    }

    private func saveText() {
        let changes = text.changes
        guard !changes.isEmpty else { return }
        write(changes, actionName: "Edit Item") { _ in }
    }

    private func setDue(_ due: DueDate?) {
        guard due != item.due else { return }
        let actionName = switch (item.due, due) {
        case (_, nil): "Remove Date"
        case (nil, _): "Add Date"
        case let (old?, new?) where old.day == new.day: new.minute == nil ? "Remove Time" : "Change Time"
        default: "Change Date"
        }
        update(actionName) { $0.due = due }
    }

    /// A chip write also carries the text the user changed: a date or kind
    /// change can move the row to another section, which rebuilds this
    /// editor from the store — unsaved text would otherwise come back stale.
    private func update(_ actionName: String, _ edit: (inout ItemEdit) -> Void) {
        write(text.changes, actionName: actionName, edit)
    }

    private func write(_ changes: ItemTextDraft.Changes, actionName: String, _ edit: (inout ItemEdit) -> Void) {
        // Deleted (swiped away, or on another device): nothing to save into.
        guard store.item(item.id) != nil else { return }
        perform {
            let combined: (inout ItemEdit) -> Void = {
                changes.apply(to: &$0)
                edit(&$0)
            }
            if let save {
                try save(item.id, actionName, combined)
            } else {
                try store.updateItem(item.id, combined)
            }
            text.didSave(changes)
        }
    }
}
