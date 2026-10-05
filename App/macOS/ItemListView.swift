import ScribeCore
import SwiftUI

/// The second column: the agenda for Upcoming (spec §6), open tasks, memos
/// and a collapsed Done group for a category or the Inbox (spec §9.2), or
/// search results grouped by category. Click selects; double-click or
/// Return edits in place; Space completes; ⌘⌫ deletes (spec §9.3).
struct ItemListView: View {
    let store: any ItemStore
    var focus: FocusState<MacRouter.Focus?>.Binding

    @Environment(MacRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        let categories = store.categories
        let content = ListContent.make(router: router, store: store, categories: categories)
        List(selection: $router.selectedItemID) {
            ForEach(content.sections) { section in
                Section {
                    rows(section.items, section: section, categories: categories)
                } header: {
                    if let title = section.title {
                        Text(title).foregroundStyle(section.isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                }
            }
            if !content.done.isEmpty {
                Section {
                    DisclosureGroup("Done (\(content.done.count))", isExpanded: $router.showsDone) {
                        rows(content.done, section: nil, categories: categories)
                    }
                }
            }
        }
        .listStyle(.inset)
        .focused(focus, equals: .list)
        .onKeyPress(.space) { router.run(.toggleDone) ? .handled : .ignored }
        .onDeleteCommand { router.run(.delete) }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let item = store.item(id) {
                MacItemMenu(item: item, categories: categories)
            }
        } primaryAction: { ids in
            guard let id = ids.first else { return }
            router.selectedItemID = id
            router.expandedItemID = id
        }
        .onChange(of: content.visibleIDs, initial: true) { old, new in
            router.visibleItemIDs = new
            // The selected row left the list (deleted, completed out of the
            // agenda, moved): select its neighbour so the keyboard keeps going.
            guard let selected = router.selectedItemID, !new.contains(selected) else { return }
            let next = ListSelection.afterRemoving(selected, from: old)
            router.selectedItemID = next.flatMap { new.contains($0) ? $0 : nil }
        }
        .overlay {
            if let empty = content.empty {
                ContentUnavailableView(empty.title, systemImage: empty.symbol, description: empty.description.map(Text.init))
            }
        }
        .navigationTitle(content.title)
    }

    private func rows(_ items: [ItemSnapshot], section: ListContent.Section?, categories: [CategorySnapshot]) -> some View {
        ForEach(items) { item in
            MacItemRow(
                store: store,
                item: item,
                categories: categories,
                showsDay: section?.showsDay ?? true,
                showsCategory: section?.showsCategory ?? false
            )
        }
    }
}

/// What the list shows for the sidebar selection or the search.
private struct ListContent {
    struct Section: Identifiable {
        let id: String
        let title: String?
        var isOverdue = false
        let items: [ItemSnapshot]
        var showsDay = true
        var showsCategory = false
    }

    struct Empty {
        let title: String
        let symbol: String
        var description: String?
    }

    var title: String
    var sections: [Section] = []
    /// Done tasks of a category or the Inbox, in a collapsed group.
    var done: [ItemSnapshot] = []
    var showsDone = false
    var empty: Empty?

    /// Row order on screen.
    var visibleIDs: [UUID] {
        sections.flatMap { $0.items.map(\.id) } + (showsDone ? done.map(\.id) : [])
    }

    @MainActor
    static func make(router: MacRouter, store: any ItemStore, categories: [CategorySnapshot]) -> ListContent {
        if router.isSearching {
            return search(router.searchText.trimmingCharacters(in: .whitespacesAndNewlines), store: store, categories: categories)
        }
        switch router.sidebar {
        case .upcoming:
            return upcoming(store: store)
        case .inbox:
            return list("Inbox", items: store.items(.inbox), showsDone: router.showsDone)
        case .category(let id):
            let name = categories.first { $0.id == id }?.displayName ?? "Category"
            return list(name, items: store.items(.category(id)), showsDone: router.showsDone)
        }
    }

    @MainActor
    private static func upcoming(store: any ItemStore) -> ListContent {
        let now = Date()
        let agenda = store.agenda(.all, now: now)
        let labels = DueLabels()
        let today = LocalDay(now, calendar: labels.calendar)
        var content = ListContent(title: "Upcoming")
        if !agenda.overdue.isEmpty {
            content.sections.append(Section(id: "overdue", title: "Overdue", isOverdue: true, items: agenda.overdue, showsCategory: true))
        }
        for day in agenda.days {
            content.sections.append(Section(id: day.day.isoString, title: labels.dayTitle(day.day, today: today), items: day.items, showsDay: false, showsCategory: true))
        }
        if agenda.isEmpty {
            content.empty = Empty(title: "Nothing coming up", symbol: "calendar", description: "Items with a date in the next 7 days show up here.")
        }
        return content
    }

    private static func list(_ title: String, items: [ItemSnapshot], showsDone: Bool) -> ListContent {
        let contents = CategoryContents(items: items)
        var content = ListContent(title: title, done: contents.done, showsDone: showsDone)
        if !contents.openTasks.isEmpty {
            content.sections.append(Section(id: "tasks", title: nil, items: contents.openTasks))
        }
        if !contents.memos.isEmpty {
            content.sections.append(Section(id: "memos", title: "Memos", items: contents.memos))
        }
        if contents.isEmpty {
            content.empty = Empty(title: "Nothing here yet", symbol: "tray", description: "Add something with the field below.")
        }
        return content
    }

    @MainActor
    private static func search(_ query: String, store: any ItemStore, categories: [CategorySnapshot]) -> ListContent {
        let groups = SearchGroup.make(items: store.items(.search(query)), categories: categories)
        var content = ListContent(title: "Search")
        content.sections = groups.map { group in
            Section(id: group.id, title: group.category?.displayName ?? "Inbox", items: group.items)
        }
        if groups.isEmpty {
            content.empty = Empty(title: "No Results for \u{201C}\(query)\u{201D}", symbol: "magnifyingglass", description: "Titles and notes, including done items.")
        }
        return content
    }
}
