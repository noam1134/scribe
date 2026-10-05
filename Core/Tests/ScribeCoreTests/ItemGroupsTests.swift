import Foundation
import Testing
@testable import ScribeCore

struct ItemGroupsTests {
    @Test func categoryContentsSplitsAndOrders() {
        let open = ItemSnapshot(title: "open")
        let memo = ItemSnapshot(title: "memo", kind: .memo)
        let doneEarly = ItemSnapshot(title: "done early", isDone: true, doneAt: Date(timeIntervalSince1970: 100))
        let doneLate = ItemSnapshot(title: "done late", isDone: true, doneAt: Date(timeIntervalSince1970: 200))
        let contents = CategoryContents(items: [doneEarly, open, memo, doneLate])
        #expect(contents.openTasks.map(\.title) == ["open"])
        #expect(contents.memos.map(\.title) == ["memo"])
        #expect(contents.done.map(\.title) == ["done late", "done early"])
        #expect(!contents.isEmpty)
        #expect(CategoryContents(items: []).isEmpty)
    }

    @Test func searchGroupsInboxFirstThenSortOrder() {
        let work = CategorySnapshot(name: "Work", sortIndex: 1)
        let trip = CategorySnapshot(name: "Trip", sortIndex: 0)
        let empty = CategorySnapshot(name: "Empty", sortIndex: 2)
        let items = [
            ItemSnapshot(title: "w", categoryID: work.id),
            ItemSnapshot(title: "i"),
            ItemSnapshot(title: "t", categoryID: trip.id),
        ]
        let groups = SearchGroup.make(items: items, categories: [work, trip, empty])
        #expect(groups.map { $0.category?.name ?? "Inbox" } == ["Inbox", "Trip", "Work"])
        #expect(groups.map { $0.items.map(\.title) } == [["i"], ["t"], ["w"]])
    }
}
