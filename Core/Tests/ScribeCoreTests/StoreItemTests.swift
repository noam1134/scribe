import Foundation
import Observation
import SwiftData
import Testing
@testable import ScribeCore

@MainActor
struct StoreItemTests {
    @Test func addItemTrimsTitleAndStampsCreation() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let id = try store.addItem(ItemDraft(title: "  Buy milk  ", body: "2%"))
        let item = try #require(store.item(id))
        #expect(item.title == "Buy milk")
        #expect(item.body == "2%")
        #expect(item.kind == .task)
        #expect(item.categoryID == nil)
        #expect(item.createdAt == clock.now)
        #expect(item.updatedAt == clock.now)
        #expect(store.items(.inbox).map(\.id) == [id])
    }

    @Test func addItemRejectsBlankTitle() throws {
        let store = try makeStore()
        #expect(throws: StoreError.emptyTitle) { try store.addItem(ItemDraft(title: "   ")) }
        #expect(store.items(.inbox).isEmpty)
    }

    @Test func addItemRejectsUnknownCategory() throws {
        let store = try makeStore()
        let missing = UUID()
        #expect(throws: StoreError.categoryNotFound(missing)) {
            try store.addItem(ItemDraft(title: "x", categoryID: missing))
        }
    }

    @Test func updateItemEditsFieldsAndBumpsUpdatedAt() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let id = try store.addItem(ItemDraft(title: "Report"))
        clock.advance(minutes: 5)
        let due = DueDate(day: LocalDay(2026, 10, 9), minute: 9 * 60)
        try store.updateItem(id) {
            $0.title = "Q3 report"
            $0.body = "numbers"
            $0.categoryID = work
            $0.due = due
        }
        let item = try #require(store.item(id))
        #expect(item.title == "Q3 report")
        #expect(item.body == "numbers")
        #expect(item.categoryID == work)
        #expect(item.due == due)
        #expect(item.updatedAt == clock.now)
        #expect(item.createdAt < item.updatedAt)
    }

    @Test func updateItemRejectsBlankTitleAndLeavesItemUnchanged() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Keep me"))
        #expect(throws: StoreError.emptyTitle) { try store.updateItem(id) { $0.title = " " } }
        #expect(store.item(id)?.title == "Keep me")
    }

    @Test func switchingToMemoClearsDone() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "x"))
        try store.setDone(id, true)
        try store.updateItem(id) { $0.kind = .memo }
        let item = try #require(store.item(id))
        #expect(item.kind == .memo)
        #expect(item.isDone == false)
        #expect(item.doneAt == nil)
    }

    @Test func setDoneStampsAndClears() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let id = try store.addItem(ItemDraft(title: "x"))
        clock.advance(minutes: 1)
        try store.setDone(id, true)
        #expect(store.item(id)?.isDone == true)
        #expect(store.item(id)?.doneAt == clock.now)
        try store.setDone(id, false)
        #expect(store.item(id)?.isDone == false)
        #expect(store.item(id)?.doneAt == nil)
    }

    @Test func setDoneIgnoresMemos() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Door code 4821", kind: .memo))
        try store.setDone(id, true)
        #expect(store.item(id)?.isDone == false)
    }

    @Test func deleteThenRestoreKeepsEverything() throws {
        let store = try makeStore()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let id = try store.addItem(ItemDraft(title: "x", body: "b", categoryID: work, due: DueDate(day: LocalDay(2026, 10, 6))))
        let before = try #require(store.item(id))
        try store.deleteItem(id)
        #expect(store.item(id) == nil)
        try store.restoreItem(before)
        #expect(store.item(id) == before)
        try store.restoreItem(before) // second restore is a no-op
        #expect(store.items(.category(work)).count == 1)
    }

    @Test func missingItemThrows() throws {
        let store = try makeStore()
        let missing = UUID()
        #expect(throws: StoreError.itemNotFound(missing)) { try store.setDone(missing, true) }
        #expect(throws: StoreError.itemNotFound(missing)) { try store.deleteItem(missing) }
    }

    @Test func categoryListOrdersDatedFirstThenNewestUndated() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let old = try store.addItem(ItemDraft(title: "old undated"))
        clock.advance(minutes: 1)
        let new = try store.addItem(ItemDraft(title: "new undated"))
        let later = try store.addItem(ItemDraft(title: "later", due: DueDate(day: LocalDay(2026, 10, 9))))
        let soonTimed = try store.addItem(ItemDraft(title: "soon timed", due: DueDate(day: LocalDay(2026, 10, 6), minute: 600)))
        let soonUntimed = try store.addItem(ItemDraft(title: "soon untimed", due: DueDate(day: LocalDay(2026, 10, 6))))
        #expect(store.items(.inbox).map(\.id) == [soonUntimed, soonTimed, later, new, old])
    }

    @Test func searchMatchesTitleOrBodyIgnoringCaseIncludingDone() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let a = try store.addItem(ItemDraft(title: "Book FLIGHTS"))
        clock.advance(minutes: 1)
        let b = try store.addItem(ItemDraft(title: "Hotel", body: "near the flights desk"))
        try store.setDone(a, true)
        _ = try store.addItem(ItemDraft(title: "Unrelated"))
        #expect(Set(store.items(.search("flights")).map(\.id)) == [a, b])
        #expect(store.items(.search("   ")).isEmpty)
        #expect(store.items(.search("לקנות")).isEmpty)
    }

    @Test func allReturnsEveryItemIncludingDoneAndInbox() throws {
        let store = try makeStore()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let inbox = try store.addItem(ItemDraft(title: "inbox"))
        let done = try store.addItem(ItemDraft(title: "done", categoryID: work))
        let memo = try store.addItem(ItemDraft(title: "memo", kind: .memo, categoryID: work, due: DueDate(day: LocalDay(2026, 10, 6))))
        try store.setDone(done, true)
        let all = store.items(.all)
        #expect(Set(all.map(\.id)) == [inbox, done, memo])
        #expect(all.first?.id == memo, "dated items first, like a category list")
    }

    /// What widgets read: open items with a date, never the done tasks
    /// that pile up over the years.
    @Test func datedOpenItemsHoldEverythingAnAgendaCanShow() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let late = try store.addItem(ItemDraft(title: "late", categoryID: work, due: DueDate(day: LocalDay(2026, 10, 1))))
        let soon = try store.addItem(ItemDraft(title: "soon", due: DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60)))
        let memo = try store.addItem(ItemDraft(title: "memo", kind: .memo, due: DueDate(day: LocalDay(2026, 10, 5))))
        let far = try store.addItem(ItemDraft(title: "far", due: DueDate(day: LocalDay(2027, 1, 1))))
        _ = try store.addItem(ItemDraft(title: "undated"))
        _ = try store.addItem(ItemDraft(title: "undated memo", kind: .memo))
        let done = try store.addItem(ItemDraft(title: "done", due: DueDate(day: LocalDay(2026, 10, 5))))
        try store.setDone(done, true)

        let dated = store.datedOpenItems()
        #expect(dated.map(\.id) == [late, memo, soon, far])
        for moment in [clock.now, TestCalendar.date(2026, 10, 6, 0, 0), TestCalendar.date(2026, 12, 30)] {
            #expect(AgendaBuilder.build(items: dated, scope: .all, now: moment, calendar: TestCalendar.jerusalem)
                == store.agenda(.all, now: moment))
        }
    }

    @Test func hebrewSearchWorks() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "לקנות חלב"))
        #expect(store.items(.search("חלב")).map(\.id) == [id])
    }

    @Test func readsAreObservable() throws {
        final class Flag: @unchecked Sendable { var fired = false }
        let store = try makeStore()
        let flag = Flag()
        withObservationTracking {
            _ = store.items(.inbox)
        } onChange: {
            flag.fired = true
        }
        try store.addItem(ItemDraft(title: "x"))
        #expect(flag.fired)
    }

    @Test func refreshNotifiesObservers() throws {
        final class Flag: @unchecked Sendable { var fired = false }
        let store = try makeStore()
        let flag = Flag()
        withObservationTracking {
            _ = store.categories
        } onChange: {
            flag.fired = true
        }
        store.refresh()
        #expect(flag.fired)
    }

    /// The widget extension and intents open the same file with their own
    /// container; the app's next read must see their writes.
    @Test func readsSeeWritesFromAnotherContainer() throws {
        let url = URL.temporaryDirectory.appending(path: "scribe-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
            }
        }
        let schema = StoreFactory.schema
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        }
        let app = SwiftDataItemStore(container: try open(), calendar: TestCalendar.jerusalem)
        let widget = SwiftDataItemStore(container: try open(), calendar: TestCalendar.jerusalem)
        let id = try app.addItem(ItemDraft(title: "from app"))
        _ = app.items(.inbox)
        try widget.setDone(id, true)
        try widget.addItem(ItemDraft(title: "from widget"))
        try widget.updateItem(id) { $0.title = "renamed by widget" }
        #expect(app.item(id)?.title == "renamed by widget")
        #expect(app.item(id)?.isDone == true)
        #expect(Set(app.items(.inbox).map(\.title)) == ["renamed by widget", "from widget"])
    }

    /// The app's CloudKit mirroring exports changes it finds in the store's
    /// persistent history, so a write made by a container without CloudKit
    /// (the widget extension's) must be recorded there too (spec §4.3, §12).
    @Test func writesWithoutCloudKitAreInPersistentHistory() throws {
        let url = URL.temporaryDirectory.appending(path: "scribe-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
            }
        }
        let schema = StoreFactory.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let widget = SwiftDataItemStore(container: container, calendar: TestCalendar.jerusalem)
        let id = try widget.addItem(ItemDraft(title: "from widget"))
        try widget.setDone(id, true)

        let reader = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let transactions = try ModelContext(reader).fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        let changes = transactions.flatMap(\.changes)
        #expect(transactions.count >= 2, "one transaction per save")
        #expect(changes.contains { if case .insert = $0 { true } else { false } })
        #expect(changes.contains { if case .update = $0 { true } else { false } })
    }
}
