import ScribeCore
import SwiftUI

/// One item: checkbox (tasks) or note glyph (memos), the title in its own
/// text direction, and the due/category line — or, while it is expanded,
/// the inline editor in the title's place (Things-style, spec §9.3).
struct MacItemRow: View {
    let store: any ItemStore
    let item: ItemSnapshot
    /// Read once by the list, not per row: each store read fetches items.
    let categories: [CategorySnapshot]
    var showsDay = true
    var showsCategory = false

    @Environment(MacRouter.self) private var router

    private var category: CategorySnapshot? {
        item.categoryID.flatMap { id in categories.first { $0.id == id } }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            marker
            if router.expandedItemID == item.id {
                ItemEditor(store: store, item: item, categories: categories, perform: router.perform) {
                    router.closeEditor()
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutDirection(of: item.title)
                    if let subtitle = item.subtitle(category: category, showsDay: showsDay, showsCategory: showsCategory) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var marker: some View {
        switch item.kind {
        case .task:
            Button {
                router.setDone(item, !item.isDone)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(category?.color ?? .accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark not done" : "Mark done")
        case .memo:
            Image(systemName: "note.text")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }
}

/// The right-click menu for a row: move, task↔memo, date, done, edit,
/// delete. Every change here is undoable with ⌘Z.
struct MacItemMenu: View {
    let item: ItemSnapshot
    let categories: [CategorySnapshot]

    @Environment(MacRouter.self) private var router

    var body: some View {
        Button("Edit") {
            router.selectedItemID = item.id
            router.expandedItemID = item.id
        }
        if item.kind == .task {
            Button(item.isDone ? "Mark as Not Done" : "Mark as Done") { router.setDone(item, !item.isDone) }
        }
        Divider()
        // No Inbox to move into (spec §19).
        Menu("Move to") {
            ForEach(categories) { category in
                Button(category.displayName) {
                    router.update(item, "Move to \u{201C}\(category.name)\u{201D}") { $0.categoryID = category.id }
                }
                .disabled(category.id == item.categoryID)
            }
        }
        Menu("Date") {
            let calendar = Calendar.autoupdatingCurrent
            let today = LocalDay(Date(), calendar: calendar)
            ForEach(DatePreset.allCases, id: \.self) { preset in
                Button(preset.title) {
                    router.update(item, "Change Date") { $0.due = preset.applied(to: $0.due, today: today, calendar: calendar) }
                }
            }
            Button("No Date") { router.update(item, "Remove Date") { $0.due = nil } }
                .disabled(item.due == nil)
        }
        Button(item.kind == .task ? "Make Memo" : "Make Task") {
            router.update(item, item.kind == .task ? "Make Memo" : "Make Task") { $0.kind = item.kind == .task ? .memo : .task }
        }
        Divider()
        Button("Delete", role: .destructive) { router.delete(item) }
    }
}
