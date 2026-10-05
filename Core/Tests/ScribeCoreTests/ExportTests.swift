import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct ExportTests {
    @Test func exportRoundTripsEveryField() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let work = try store.addCategory(CategoryDraft(name: "Work", emoji: "💼", colorName: "indigo"))
        let report = try store.addItem(ItemDraft(title: "Report", body: "Q3", categoryID: work, due: DueDate(day: LocalDay(2026, 10, 6), minute: 540)))
        clock.advance(minutes: 1)
        let memo = try store.addItem(ItemDraft(title: "Door code 4821", kind: .memo))
        clock.advance(minutes: 1)
        try store.setDone(report, true)

        let document = try ExportDocument.decoder().decode(ExportDocument.self, from: store.exportJSON())

        #expect(document.version == 1)
        #expect(document.exportedAt == clock.now)
        #expect(document.categories == [ExportedCategory(id: work, name: "Work", emoji: "💼", colorName: "indigo", sortIndex: 0)])
        #expect(document.items.map(\.id) == [report, memo])
        let first = document.items[0]
        #expect(first.title == "Report")
        #expect(first.body == "Q3")
        #expect(first.kind == .task)
        #expect(first.categoryID == work)
        #expect(first.dueDay == "2026-10-06")
        #expect(first.dueMinute == 540)
        #expect(first.isDone)
        #expect(first.doneAt == clock.now)
        #expect(document.items[1].kind == .memo)
        #expect(document.items[1].categoryID == nil)
    }

    @Test func exportIsStableJSON() throws {
        let store = try makeStore()
        try store.addItem(ItemDraft(title: "x"))
        let text = try #require(String(data: try store.exportJSON(), encoding: .utf8))
        #expect(text.contains("\"version\" : 1"))
        #expect(text.contains("\"kind\" : \"task\""))
    }

    @Test func exportKeepsMilliseconds() throws {
        let clock = TestClock()
        clock.now = clock.now.addingTimeInterval(0.25)
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "x"))
        let data = try store.exportJSON()
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"createdAt\" : \"2026-10-05T07:00:00.250Z\""))
        let document = try ExportDocument.decoder().decode(ExportDocument.self, from: data)
        #expect(document.items.first?.createdAt == clock.now)
    }
}
