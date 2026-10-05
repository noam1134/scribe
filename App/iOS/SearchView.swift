import ScribeCore
import SwiftUI

/// Title + body search across everything, including done items, grouped by
/// category (spec §9.2).
struct SearchView: View {
    let store: any ItemStore
    @State private var query = ""

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = SearchGroup.make(items: store.items(.search(trimmed)), categories: store.categories)
        List {
            ForEach(groups) { group in
                Section(group.category?.displayName ?? "Inbox") {
                    ForEach(group.items) { ItemRow(store: store, item: $0, showsCategory: false) }
                }
            }
        }
        .overlay {
            if trimmed.isEmpty {
                ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Titles and notes, including done items."))
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            }
        }
        .searchable(text: $query)
        .navigationTitle("Search")
    }
}
