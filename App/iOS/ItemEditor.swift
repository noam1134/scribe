import ScribeCore
import SwiftUI

/// A tapped row's inline editor (spec §9.2): title, notes, and a row of
/// glass chips for date, category and kind. Text saves on Return (which also
/// closes the editor) and when the editor goes away; chips save immediately.
struct ItemEditor: View {
    let store: any ItemStore
    let item: ItemSnapshot
    let categories: [CategorySnapshot]
    let close: () -> Void

    private enum InlinePicker { case date, time }

    @Environment(AppRouter.self) private var router
    @State private var title: String
    @State private var notes: String
    @State private var picker: InlinePicker?

    private let calendar = Calendar.autoupdatingCurrent
    private var today: LocalDay { LocalDay(Date(), calendar: calendar) }

    init(store: any ItemStore, item: ItemSnapshot, categories: [CategorySnapshot], close: @escaping () -> Void) {
        self.store = store
        self.item = item
        self.categories = categories
        self.close = close
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title)
                .font(.body.weight(.medium))
                .layoutDirection(of: title)
                .submitLabel(.done)
                .onSubmit {
                    saveText()
                    close()
                }
                .accessibilityIdentifier("titleField")
            TextField("Notes", text: $notes, axis: .vertical)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1...6)
                .layoutDirection(of: notes)
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
        .onDisappear(perform: saveText)
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
        return Menu {
            Picker("Category", selection: categoryBinding) {
                Label("Inbox", systemImage: "tray").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.displayName).tag(UUID?.some(category.id))
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

    private var categoryBinding: Binding<UUID?> {
        Binding(get: { item.categoryID }, set: { id in update { $0.categoryID = id } })
    }

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

    private func saveText() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.title || notes != item.body else { return }
        guard !trimmed.isEmpty else {
            title = item.title // an empty title isn't allowed (spec §13); put the old one back
            return
        }
        update {
            $0.title = trimmed
            $0.body = notes
        }
    }

    private func setDue(_ due: DueDate?) {
        guard due != item.due else { return }
        update { $0.due = due }
    }

    /// Every write also carries the text typed so far: a date or kind change
    /// can move the row to another section, which rebuilds this editor from
    /// the store — unsaved text would otherwise come back stale.
    private func update(_ edit: (inout ItemEdit) -> Void) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        router.perform {
            try store.updateItem(item.id) {
                if !trimmed.isEmpty { $0.title = trimmed }
                $0.body = notes
                edit(&$0)
            }
        }
    }
}
