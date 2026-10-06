import ScribeCore
import SwiftUI

/// One item: checkbox (tasks) or note glyph (memos), the title in its own
/// text direction, and its details — the due/category/checklist line (on
/// the title's line when both fit) and the notes — shown until a click
/// hides them; a click shows them again, a double-click opens the inline
/// editor in the title's place (Things-style, spec §9.3).
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
                ItemEditor(
                    store: store,
                    item: item,
                    categories: categories,
                    perform: router.perform,
                    // Through the window's undo, so ⌘Z after a chip undoes it.
                    save: { id, actionName, edit in try router.undoable.update(id, actionName: actionName, edit) },
                    takeTitleFocus: { router.takeTitleFocus(for: item.id) }
                ) {
                    router.closeEditor()
                }
                // Below only: the title stays where the row showed it.
                .padding(.bottom, 4)
            } else {
                let showsDetails = router.showsDetails(of: item.id)
                VStack(alignment: .leading, spacing: 1) {
                    // The details' line beside the title when both fit;
                    // under it when they don't, so a long title isn't squeezed.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            title.fixedSize()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutDirection(of: item.title)
                            if showsDetails { secondaryLine.fixedSize() }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            title
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutDirection(of: item.title)
                            if showsDetails { secondaryLine }
                        }
                    }
                    if showsDetails && !item.body.isEmpty {
                        Text(item.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutDirection(of: item.body)
                    }
                }
                .contentShape(.rect)
                // A click on the text selects the row and shows or hides
                // its details; a double-click edits.
                .onTapGesture(count: 2) { router.edit(item.id) }
                .onTapGesture {
                    router.selectedItemID = item.id
                    router.focusRequest = .list
                    withAnimation(.snappy) { router.toggleDetails(of: item.id) }
                }
            }
        }
        .padding(.vertical, 1)
    }

    private var title: some View {
        Text(item.title)
            .strikethrough(item.isDone)
            .foregroundStyle(item.isDone ? .secondary : .primary)
    }

    /// Date, category and checklist progress; nothing when there are none.
    @ViewBuilder private var secondaryLine: some View {
        let subtitle = item.subtitle(category: category, showsDay: showsDay, showsCategory: showsCategory)
        let progress = ChecklistProgress(item.checklist)
        if subtitle != nil || progress != nil {
            HStack(spacing: 6) {
                if let subtitle { Text(subtitle) }
                if let progress { ChecklistBadge(progress: progress) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var marker: some View {
        switch item.kind {
        case .task:
            Button {
                router.setDone(item, !item.isDone)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .imageScale(.large)
                    .foregroundStyle(category?.color ?? .accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark not done" : "Mark done")
        case .memo:
            Image(systemName: "note.text")
                .font(.body)
                .imageScale(.large)
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
        Button("Edit") { router.edit(item.id) }
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
