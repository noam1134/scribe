import Foundation
import Testing
@testable import ScribeCore

/// The store read the notification scheduler plans from.
@MainActor
struct NotificationStoreTests {
    @Test func allReturnsEveryItemIncludingDoneAndInbox() throws {
        let store = try makeStore()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let far = try store.addItem(ItemDraft(title: "far future", categoryID: work, due: DueDate(day: LocalDay(2027, 3, 1), minute: 9 * 60)))
        let inbox = try store.addItem(ItemDraft(title: "inbox, undated"))
        let memo = try store.addItem(ItemDraft(title: "memo", kind: .memo, categoryID: work, due: DueDate(day: LocalDay(2026, 10, 6))))
        let done = try store.addItem(ItemDraft(title: "done", categoryID: work))
        try store.setDone(done, true)

        let all = store.items(.all)
        #expect(Set(all.map(\.id)) == [far, inbox, memo, done])
        #expect(all.first { $0.id == done }?.isDone == true)
        // Same order as a category list: dated by due date, then undated newest first.
        #expect(all.map(\.id).prefix(2) == [memo, far])
    }
}
