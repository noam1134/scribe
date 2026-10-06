import ScribeCore
import SwiftUI

/// One item in any list: checkbox (tasks) or note glyph (memos), title in
/// its own text direction, due/category/checklist line. Tap to edit in place (the
/// editor takes the title's place; a tap between its fields closes it);
/// in a card, swipe right to complete, left to delete with Undo (spec §9.2).
struct ItemRow: View {
    let store: any ItemStore
    let item: ItemSnapshot
    /// Read once by the list, not per row: each store read fetches items.
    let categories: [CategorySnapshot]
    var showsDay = true
    var showsCategory = true
    /// Completing hides the row here, so offer Undo (Upcoming; Lists
    /// without Show Completed).
    var offersUndoOnComplete = false

    @Environment(AppRouter.self) private var router
    @Environment(UndoCenter.self) private var undo

    private var category: CategorySnapshot? {
        item.categoryID.flatMap { id in categories.first { $0.id == id } }
    }

    private var isExpanded: Bool { router.expandedItemID == item.id }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            marker
            if isExpanded {
                ItemEditor(store: store, item: item, categories: categories, perform: router.perform) { setExpanded(false) }
            } else {
                // The date on the title's line when both fit; under the
                // title when they don't, so a long title isn't squeezed.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title.fixedSize()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutDirection(of: item.title)
                        secondaryLine.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        title
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutDirection(of: item.title)
                        secondaryLine
                    }
                }
                .contentShape(.rect)
                .onTapGesture { setExpanded(true) }
            }
        }
        .background {
            if isExpanded {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { setExpanded(false) }
            }
        }
        .contextMenu { menu }
    }

    @ViewBuilder private var marker: some View {
        switch item.kind {
        case .task:
            Button { toggleDone() } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .imageScale(.large)
                    .foregroundStyle(category?.color ?? .accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark not done" : "Mark done")
            .accessibilityIdentifier("checkbox-\(item.title)")
        case .memo:
            Image(systemName: "note.text")
                .font(.body)
                .imageScale(.large)
                .foregroundStyle(.tertiary)
        }
    }

    private var title: some View {
        Text(item.title)
            .strikethrough(item.isDone)
            .foregroundStyle(item.isDone ? .secondary : .primary)
    }

    /// Date, category and checklist progress; nothing when there are none.
    @ViewBuilder private var secondaryLine: some View {
        let subtitle = subtitle
        let progress = ChecklistProgress(item.checklist)
        if subtitle != nil || progress != nil {
            HStack(spacing: 6) {
                if let subtitle { Text(subtitle) }
                if let progress { ChecklistBadge(progress: progress) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String? {
        item.subtitle(category: category, showsDay: showsDay, showsCategory: showsCategory)
    }

    @ViewBuilder private var menu: some View {
        Menu("Move to", systemImage: "folder") {
            ForEach(categories) { category in
                Button(category.displayName) {
                    update { $0.categoryID = category.id }
                    // Lists shows it where it went.
                    router.lists.expand(.category(category.id))
                }
            }
        }
        Button(item.kind == .task ? "Make Memo" : "Make Task",
               systemImage: item.kind == .task ? "note.text" : "checkmark.circle") {
            update { $0.kind = item.kind == .task ? .memo : .task }
        }
        Menu("Date", systemImage: "calendar") {
            let calendar = Calendar.autoupdatingCurrent
            let today = LocalDay(Date(), calendar: calendar)
            ForEach(DatePreset.allCases, id: \.self) { preset in
                Button(preset.title) { update { $0.due = preset.applied(to: $0.due, today: today, calendar: calendar) } }
            }
            Button("No Date") { update { $0.due = nil } }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { delete() }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.snappy) { router.expandedItemID = expanded ? item.id : nil }
    }

    // Animated, so the rows around a completed, moved or deleted one close up.
    private func toggleDone() {
        let snapshot = item
        withAnimation(.snappy) { router.perform {
            try store.setDone(snapshot.id, !snapshot.isDone)
            if offersUndoOnComplete && !snapshot.isDone {
                undo.offer("Completed “\(snapshot.title)”") { try store.setDone(snapshot.id, false) }
            }
        } }
    }

    private func update(_ edit: (inout ItemEdit) -> Void) {
        withAnimation(.snappy) { router.perform { try store.updateItem(item.id, edit) } }
    }

    private func delete() {
        let snapshot = item
        withAnimation(.snappy) { router.perform {
            try store.deleteItem(snapshot.id)
            if router.expandedItemID == snapshot.id { router.expandedItemID = nil }
            undo.offer("Deleted “\(snapshot.title)”") { try store.restoreItem(snapshot) }
        } }
    }
}
