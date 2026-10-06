import Foundation
import Testing
@testable import ScribeCore

/// Items Claude queued become Scribe items, each in a real category, once.
@MainActor
struct MailboxIntakeTests {
    let store: SwiftDataItemStore
    let thailand: UUID
    let cafe: UUID

    init() throws {
        store = try makeStore()
        thailand = try store.addCategory(CategoryDraft(name: "Thailand", colorName: "blue"))
        cafe = try store.addCategory(CategoryDraft(name: "Café", colorName: "red"))
    }

    func collect(_ items: [MailboxItem], ledger: inout MailboxLedger) -> MailboxIntake.Outcome {
        MailboxIntake.collect(items, into: store, ledger: &ledger)
    }

    func collect(_ items: [MailboxItem]) -> MailboxIntake.Outcome {
        var ledger = MailboxLedger()
        return collect(items, ledger: &ledger)
    }

    @Test func filesIntoTheCategoryWithThatNameIgnoringCaseAndAccents() throws {
        let outcome = collect([
            MailboxItem(id: "1", title: "Book flights", category: "thailand", dueDate: "2026-10-09", dueTime: "09:30", notes: " window seat "),
            MailboxItem(id: "2", title: "Flat white", category: "CAFE", kind: .memo),
        ])
        #expect(outcome.acknowledged == ["1", "2"])
        #expect(outcome.createdCategories.isEmpty)
        let flights = try #require(store.item(outcome.added[0]))
        #expect(flights.title == "Book flights")
        #expect(flights.body == "window seat")
        #expect(flights.categoryID == thailand)
        #expect(flights.due == DueDate(day: LocalDay(2026, 10, 9), minute: 9 * 60 + 30))
        #expect(flights.kind == .task)
        let coffee = try #require(store.item(outcome.added[1]))
        #expect(coffee.categoryID == cafe)
        #expect(coffee.kind == .memo)
    }

    @Test func aNewCategoryIsCreatedOnceWithAnUnusedColor() throws {
        let outcome = collect([
            MailboxItem(id: "1", title: "Buy milk", category: "Groceries", createCategory: true),
            MailboxItem(id: "2", title: "Eggs", category: " groceries "),
        ])
        #expect(outcome.createdCategories.count == 1)
        let groceries = try #require(store.categories.first { $0.name == "Groceries" })
        #expect(groceries.colorName == "orange", "blue and red are taken")
        #expect(outcome.added.compactMap { store.item($0)?.categoryID } == [groceries.id, groceries.id])
    }

    @Test func anUnknownNameWithoutTheFlagStillGetsItsOwnCategory() throws {
        let outcome = collect([MailboxItem(id: "1", title: "Renew passport", category: "Admin")])
        #expect(store.categories.map(\.name) == ["Thailand", "Café", "Admin"])
        #expect(store.item(outcome.added[0])?.categoryID == outcome.createdCategories.first)
    }

    @Test func aBadTimeKeepsTheDayAndABadDateDropsTheDate() throws {
        let outcome = collect([
            MailboxItem(id: "1", title: "Bad time", category: "Thailand", dueDate: "2026-10-09", dueTime: "9am"),
            MailboxItem(id: "2", title: "Bad date", category: "Thailand", dueDate: "2026-02-30", dueTime: "09:00"),
            MailboxItem(id: "3", title: "Time alone", category: "Thailand", dueTime: "09:00"),
        ])
        #expect(store.item(outcome.added[0])?.due == DueDate(day: LocalDay(2026, 10, 9)))
        #expect(store.item(outcome.added[1])?.due == nil)
        #expect(store.item(outcome.added[2])?.due == nil)
    }

    @Test func anEmptyTitleIsAcknowledgedAndDropped() {
        let outcome = collect([MailboxItem(id: "1", title: "  \n", category: "Thailand")])
        #expect(outcome.added.isEmpty)
        #expect(outcome.acknowledged == ["1"])
        #expect(store.items(.all).isEmpty)
    }

    @Test func anItemCollectedTwiceIsAddedOnce() {
        var ledger = MailboxLedger()
        let item = MailboxItem(id: "abc", title: "Call Dan", category: "Thailand")
        #expect(collect([item], ledger: &ledger).added.count == 1)
        // The acknowledgement was lost; the mailbox hands it out again.
        let again = collect([item], ledger: &ledger)
        #expect(again.added.isEmpty)
        #expect(again.acknowledged == ["abc"])
        #expect(store.items(.all).count == 1)
    }

    @Test func itemsKeepTheMailboxOrder() {
        let outcome = collect((1...3).map { MailboxItem(id: "\($0)", title: "Item \($0)", category: "Thailand") })
        #expect(outcome.added.compactMap { store.item($0)?.title } == ["Item 1", "Item 2", "Item 3"])
    }

    // MARK: Ledger

    @Test func theLedgerKeepsTheNewestFiveHundred() {
        var ledger = MailboxLedger()
        for id in 0..<520 { ledger.record("\(id)") }
        #expect(ledger.ids.count == 500)
        #expect(!ledger.contains("19"))
        #expect(ledger.contains("20") && ledger.contains("519"))
        ledger.record("519")
        #expect(ledger.ids.count == 500, "recording twice changes nothing")
    }

    @Test func theLedgerIsSavedAndRead() throws {
        let defaults = try #require(UserDefaults(suiteName: "MailboxIntakeTests-\(UUID())"))
        var ledger = MailboxLedger()
        ledger.record("a")
        ledger.record("b")
        ledger.save(to: defaults)
        #expect(MailboxLedger(from: defaults) == ledger)
        #expect(MailboxLedger(from: UserDefaults(suiteName: "MailboxIntakeTests-empty-\(UUID())")!).ids.isEmpty)
    }

    @Test(arguments: [("00:00", 0), ("09:05", 545), ("23:59", 1439)])
    func readsTimes(text: String, minute: Int) {
        #expect(MailboxIntake.minute(of: text) == minute)
    }

    @Test(arguments: ["24:00", "9:00", "09:60", "0900", "09:0a", ""])
    func refusesOtherTimes(text: String) {
        #expect(MailboxIntake.minute(of: text) == nil)
    }
}
