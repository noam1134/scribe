import ScribeCore
import SwiftUI

// The iPhone's lists — Lists, Upcoming and Search — as cards in a scroll
// view rather than `List`s: a List fades rows in and out where they stand
// while the rows below jump; here an opening editor, a completed or deleted
// item and a closing section move everything around them smoothly.

/// A scroll view of card sections on the grouped background.
struct CardScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.immediately)
    }
}

/// A titled card: a day in Upcoming, a category in Search.
struct CardSection<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
                .font(.headline)
                .padding(.leading, 20)
            ListCard { content }
        }
        .padding(.top, 14)
    }
}

/// A section's rounded card.
struct ListCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .clipShape(.rect(cornerRadius: 22))
    }
}

/// The separator between a card's rows, from where the titles start.
struct ListDivider: View {
    var body: some View {
        Divider().padding(.leading, 50).padding(.trailing, 16)
    }
}

/// A card's items: separated rows that swipe right for Done and left for
/// Delete. Completing, moving and deleting animate, so the rows around
/// close up.
struct ItemCardRows: View {
    let store: any ItemStore
    let items: [ItemSnapshot]
    let categories: [CategorySnapshot]
    var showsDay = true
    var showsCategory = true
    /// Completing hides the row here, so offer Undo.
    var offersUndoOnComplete = false
    /// The row swiped open; one at a time across the screen.
    @Binding var swiped: UUID?

    @Environment(AppRouter.self) private var router
    @Environment(UndoCenter.self) private var undo

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 { ListDivider() }
            SwipeRow(
                id: item.id,
                open: $swiped,
                isEnabled: router.expandedItemID != item.id,
                done: item.kind == .task ? { toggleDone(item) } : nil,
                delete: { delete(item) }
            ) {
                ItemRow(
                    store: store, item: item, categories: categories,
                    showsDay: showsDay, showsCategory: showsCategory,
                    offersUndoOnComplete: offersUndoOnComplete
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .id(item.id)
        }
    }

    private func toggleDone(_ item: ItemSnapshot) {
        withAnimation(.snappy) { router.perform {
            try store.setDone(item.id, !item.isDone)
            if offersUndoOnComplete && !item.isDone {
                undo.offer("Completed \u{201C}\(item.title)\u{201D}") { try store.setDone(item.id, false) }
            }
        } }
    }

    private func delete(_ item: ItemSnapshot) {
        withAnimation(.snappy) { router.perform {
            try store.deleteItem(item.id)
            if router.expandedItemID == item.id { router.expandedItemID = nil }
            undo.offer("Deleted \u{201C}\(item.title)\u{201D}") { try store.restoreItem(item) }
        } }
    }
}
