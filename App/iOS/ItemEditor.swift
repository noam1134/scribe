import ScribeCore
import SwiftUI

/// A tapped row's inline editor (spec §9.2): title, notes, and a row of
/// glass chips for date, category and kind. Text saves on Return (which also
/// closes the editor), when the editor goes away and when the app leaves the
/// foreground; chips save immediately. Only the text fields the user changed
/// are written (`ItemTextDraft`).
struct ItemEditor: View {
    let store: any ItemStore
    let item: ItemSnapshot
    let categories: [CategorySnapshot]
    let close: () -> Void

    private enum InlinePicker { case date, time }

    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var text: ItemTextDraft
    @State private var picker: InlinePicker?

    private let calendar = Calendar.autoupdatingCurrent
    private var today: LocalDay { LocalDay(Date(), calendar: calendar) }

    init(store: any ItemStore, item: ItemSnapshot, categories: [CategorySnapshot], close: @escaping () -> Void) {
        self.store = store
        self.item = item
        self.categories = categories
        self.close = close
        _text = State(initialValue: ItemTextDraft(title: item.title, notes: item.body))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $text.title)
                .font(.body.weight(.medium))
                .layoutDirection(of: text.title)
                .submitLabel(.done)
                .onSubmit {
                    finish()
                    close()
                }
                .accessibilityIdentifier("titleField")
            TextField("Notes", text: $text.notes, axis: .vertical)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1...6)
                .layoutDirection(of: text.notes)
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
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            case nil:
                EmptyView()
            }
        }
        .onDisappear(perform: finish)
        .onChange(of: scenePhase) { _, phase in
            // The app may be ended in the background: keep what was typed.
            if phase != .active { saveText() }
        }
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
                    update { $0.categoryID = option.id }
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
            update { $0.kind = item.kind == .task ? .memo : .task }
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
        write(changes) { _ in }
    }

    private func setDue(_ due: DueDate?) {
        guard due != item.due else { return }
        update { $0.due = due }
    }

    /// A chip write also carries the text the user changed: a date or kind
    /// change can move the row to another section, which rebuilds this
    /// editor from the store — unsaved text would otherwise come back stale.
    private func update(_ edit: (inout ItemEdit) -> Void) {
        write(text.changes, edit)
    }

    private func write(_ changes: ItemTextDraft.Changes, _ edit: (inout ItemEdit) -> Void) {
        // Deleted (swiped away, or on another device): nothing to save into.
        guard store.item(item.id) != nil else { return }
        router.perform {
            try store.updateItem(item.id) {
                changes.apply(to: &$0)
                edit(&$0)
            }
            text.didSave(changes)
        }
    }
}
