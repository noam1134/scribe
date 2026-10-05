import Foundation
import Testing
@testable import ScribeCore

struct ListSectionsTests {
    let work = CategorySnapshot(name: "Work", sortIndex: 1)
    let trip = CategorySnapshot(name: "Trip", sortIndex: 0)

    func titles(_ sections: [ListSection]) -> [[String]] {
        sections.map { $0.items.map(\.title) }
    }

    @Test func everyCategoryInSortOrderEvenWhenEmpty() {
        let sections = ListSections.make(items: [], categories: [work, trip], showsCompleted: false)
        #expect(sections.map(\.id) == [.category(trip.id), .category(work.id)])
        #expect(sections.map { $0.category?.name } == ["Trip", "Work"])
        #expect(sections.allSatisfy { $0.items.isEmpty })
    }

    @Test func openTasksThenMemosInStoreOrderWithoutDone() {
        let items = [
            ItemSnapshot(title: "memo 1", kind: .memo, categoryID: work.id),
            ItemSnapshot(title: "task 1", categoryID: work.id),
            ItemSnapshot(title: "done", categoryID: work.id, isDone: true, doneAt: Date(timeIntervalSince1970: 1)),
            ItemSnapshot(title: "task 2", categoryID: work.id),
            ItemSnapshot(title: "memo 2", kind: .memo, categoryID: work.id),
        ]
        let sections = ListSections.make(items: items, categories: [work], showsCompleted: false)
        #expect(titles(sections) == [["task 1", "task 2", "memo 1", "memo 2"]])
        #expect(sections[0].openCount == 4)
    }

    @Test func showsCompletedPutsDoneLastMostRecentFirst() {
        let items = [
            ItemSnapshot(title: "early", categoryID: trip.id, isDone: true, doneAt: Date(timeIntervalSince1970: 100)),
            ItemSnapshot(title: "open", categoryID: trip.id),
            ItemSnapshot(title: "late", categoryID: trip.id, isDone: true, doneAt: Date(timeIntervalSince1970: 200)),
        ]
        let sections = ListSections.make(items: items, categories: [trip], showsCompleted: true)
        #expect(titles(sections) == [["open", "late", "early"]])
        #expect(sections[0].openCount == 1)
    }

    @Test func itemsGoToTheirOwnCategory() {
        let items = [
            ItemSnapshot(title: "w", categoryID: work.id),
            ItemSnapshot(title: "t", categoryID: trip.id),
        ]
        let sections = ListSections.make(items: items, categories: [work, trip], showsCompleted: false)
        #expect(titles(sections) == [["t"], ["w"]])
    }

    @Test func inboxComesFirstOnlyWhileItHoldsSomething() {
        let without = ListSections.make(items: [ItemSnapshot(title: "w", categoryID: work.id)], categories: [work], showsCompleted: false)
        #expect(without.map(\.id) == [.category(work.id)])

        let with = ListSections.make(items: [ItemSnapshot(title: "orphan")], categories: [work], showsCompleted: false)
        #expect(with.map(\.id) == [.inbox, .category(work.id)])
        #expect(with[0].category == nil)
        #expect(with[0].openCount == 1)
    }

    /// Nothing to see: the Inbox stays away until done items are shown.
    @Test func inboxWithOnlyDoneItemsShowsWithCompleted() {
        let done = ItemSnapshot(title: "old", isDone: true, doneAt: Date())
        #expect(ListSections.make(items: [done], categories: [work], showsCompleted: false).map(\.id) == [.category(work.id)])
        #expect(ListSections.make(items: [done], categories: [work], showsCompleted: true).map(\.id) == [.inbox, .category(work.id)])
    }

    /// A category that isn't in the list (not synced yet) mustn't hide its items.
    @Test func itemOfAnUnknownCategoryIsInTheInbox() {
        let stray = ItemSnapshot(title: "stray", categoryID: UUID())
        let sections = ListSections.make(items: [stray], categories: [work], showsCompleted: false)
        #expect(sections.map(\.id) == [.inbox, .category(work.id)])
        #expect(titles(sections) == [["stray"], []])
        #expect(ListSections.sectionID(for: stray, categories: [work]) == .inbox)
    }

    @Test func sectionIDFollowsTheCategory() {
        #expect(ListSections.sectionID(for: ItemSnapshot(title: "w", categoryID: work.id), categories: [work]) == .category(work.id))
        #expect(ListSections.sectionID(for: ItemSnapshot(title: "i"), categories: [work]) == .inbox)
    }

    /// The row being edited never disappears: a done item opened from a
    /// link, or ticked while its editor is open.
    @Test func keptDoneItemStaysVisible() {
        let kept = ItemSnapshot(title: "kept", categoryID: work.id, isDone: true, doneAt: Date(timeIntervalSince1970: 1))
        let other = ItemSnapshot(title: "other", categoryID: work.id, isDone: true, doneAt: Date(timeIntervalSince1970: 2))
        let open = ItemSnapshot(title: "open", categoryID: work.id)
        let sections = ListSections.make(items: [kept, other, open], categories: [work], showsCompleted: false, keeping: kept.id)
        #expect(titles(sections) == [["open", "kept"]])
        #expect(sections[0].openCount == 1)
    }

    @Test func keptDoneInboxItemShowsTheInbox() {
        let kept = ItemSnapshot(title: "kept", isDone: true, doneAt: Date())
        let sections = ListSections.make(items: [kept], categories: [], showsCompleted: false, keeping: kept.id)
        #expect(sections.map(\.id) == [.inbox])
        #expect(titles(sections) == [["kept"]])
    }

    @Test func sectionIDsSurviveStorage() {
        let id = ListSectionID.category(UUID())
        #expect(ListSectionID(storageKey: id.storageKey) == id)
        #expect(ListSectionID(storageKey: ListSectionID.inbox.storageKey) == .inbox)
        #expect(ListSectionID(storageKey: "nonsense") == nil)
    }
}

struct ListsPreferencesTests {
    func freshDefaults() -> UserDefaults {
        let name = "scribe-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsExpandedWithDoneHidden() {
        let preferences = ListsPreferences(from: freshDefaults())
        #expect(preferences == ListsPreferences())
        #expect(!preferences.showsCompleted)
        #expect(!preferences.isCollapsed(.inbox))
        #expect(!preferences.isCollapsed(.category(UUID())))
    }

    @Test func toggleAndExpand() {
        let id = ListSectionID.category(UUID())
        var preferences = ListsPreferences()
        preferences.toggle(id)
        #expect(preferences.isCollapsed(id))
        #expect(!preferences.isCollapsed(.inbox))
        preferences.toggle(id)
        #expect(!preferences.isCollapsed(id))
        preferences.toggle(id)
        preferences.expand(id)
        #expect(!preferences.isCollapsed(id))
        preferences.expand(id)
        #expect(!preferences.isCollapsed(id))
    }

    @Test func roundTrip() {
        let defaults = freshDefaults()
        var preferences = ListsPreferences()
        preferences.toggle(.inbox)
        preferences.toggle(.category(UUID()))
        preferences.showsCompleted = true
        preferences.save(to: defaults)
        #expect(ListsPreferences(from: defaults) == preferences)
    }

    @Test func malformedStoredValuesAreIgnored() {
        let defaults = freshDefaults()
        let id = UUID()
        defaults.set(["junk", id.uuidString, ""], forKey: ListsPreferences.Keys.collapsed)
        defaults.set("not a bool", forKey: ListsPreferences.Keys.showsCompleted)
        let preferences = ListsPreferences(from: defaults)
        #expect(preferences.isCollapsed(.category(id)))
        #expect(!preferences.isCollapsed(.inbox))
        #expect(!preferences.showsCompleted)

        defaults.set(42, forKey: ListsPreferences.Keys.collapsed)
        #expect(ListsPreferences(from: defaults) == ListsPreferences())
    }
}
