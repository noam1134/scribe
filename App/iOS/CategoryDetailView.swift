import ScribeCore
import SwiftUI

/// One category (or the Inbox): open tasks, memos, then a collapsed Done
/// section (spec §9.2).
struct CategoryDetailView: View {
    let store: any ItemStore
    let destination: AppRouter.Destination

    @State private var showsDone = false

    private var filter: ItemFilter {
        switch destination {
        case .inbox: .inbox
        case .category(let id): .category(id)
        }
    }

    private var title: String {
        switch destination {
        case .inbox: "Inbox"
        case .category(let id): store.categories.first { $0.id == id }?.displayName ?? "Category"
        }
    }

    var body: some View {
        let contents = CategoryContents(items: store.items(filter))
        List {
            if !contents.openTasks.isEmpty {
                Section {
                    ForEach(contents.openTasks) { ItemRow(store: store, item: $0, showsCategory: false) }
                }
            }
            if !contents.memos.isEmpty {
                Section("Memos") {
                    ForEach(contents.memos) { ItemRow(store: store, item: $0, showsCategory: false) }
                }
            }
            if !contents.done.isEmpty {
                Section {
                    DisclosureGroup("Done (\(contents.done.count))", isExpanded: $showsDone) {
                        ForEach(contents.done) { ItemRow(store: store, item: $0, showsCategory: false) }
                    }
                }
            }
        }
        .overlay {
            if contents.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "tray", description: Text("Add something with the bar below."))
            }
        }
        .navigationTitle(title)
    }
}
