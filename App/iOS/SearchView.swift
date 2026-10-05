import ScribeCore
import SwiftUI

/// Title + body search across everything, including done items, grouped by
/// category (spec §9.2).
struct SearchView: View {
    let store: any ItemStore
    @State private var query = ""
    /// The row swiped open to show Done or Delete.
    @State private var swipedItemID: UUID?

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // No query, no fetch: the empty state needs nothing from the store.
        let categories = trimmed.isEmpty ? [] : store.categories
        let groups = trimmed.isEmpty ? [] : SearchGroup.make(items: store.items(.search(trimmed)), categories: categories)
        CardScroll {
            ForEach(groups) { group in
                CardSection {
                    Text(group.category?.displayName ?? "Inbox").foregroundStyle(.secondary)
                } content: {
                    ItemCardRows(
                        store: store, items: group.items, categories: categories, showsCategory: false,
                        swiped: $swipedItemID
                    )
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
        .navigationBarTitleDisplayMode(.inline)
    }
}
