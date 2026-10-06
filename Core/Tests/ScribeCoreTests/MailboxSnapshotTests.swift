import Foundation
import Testing
@testable import ScribeCore

/// What the app publishes to the Claude mailbox.
struct MailboxSnapshotTests {
    let calendar = TestCalendar.jerusalem
    let now = TestCalendar.monday // Mon 2026-10-05 10:00
    let work = CategorySnapshot(name: "Work", emoji: "💼", colorName: "blue", sortIndex: 0)
    let thailand = CategorySnapshot(name: "Thailand", sortIndex: 1)

    func day(_ offset: Int) -> LocalDay {
        LocalDay(2026, 10, 5).adding(days: offset, calendar: calendar)
    }

    func item(_ title: String, _ kind: ItemKind = .task, in category: CategorySnapshot? = nil, on offset: Int?, at minute: Int? = nil, done: Bool = false, created: TimeInterval = 0) -> ItemSnapshot {
        ItemSnapshot(
            title: title,
            kind: kind,
            categoryID: category?.id,
            due: offset.map { DueDate(day: day($0), minute: minute) },
            isDone: done,
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    func build(_ items: [ItemSnapshot], categories: [CategorySnapshot]? = nil, calendar: Calendar? = nil) -> MailboxSnapshot {
        MailboxSnapshotBuilder.build(categories: categories ?? [work, thailand], items: items, now: now, calendar: calendar ?? self.calendar)
    }

    @Test func categoriesInOrderWithEmoji() {
        let snapshot = build([])
        #expect(snapshot.categories == [.init(name: "Work", emoji: "💼"), .init(name: "Thailand", emoji: "")])
        #expect(snapshot.timeZone == "Asia/Jerusalem")
        #expect(snapshot.updatedAt == now)
        #expect(snapshot.version == 1)
    }

    @Test func overdueTasksThenTheNextThirtyDays() {
        let snapshot = build([
            item("Day 30", in: work, on: 30),
            item("Day 29", in: work, on: 29),
            item("Today later", in: work, on: 0, at: 18 * 60 + 5),
            item("Today", .memo, in: thailand, on: 0),
            item("Overdue", in: work, on: -3),
            item("Old memo", .memo, in: work, on: -1),
            item("Done", in: work, on: 1, done: true),
            item("Undated", in: work, on: nil),
            item("Inbox", on: 2),
        ])
        #expect(snapshot.upcoming == [
            .init(title: "Overdue", category: "Work", kind: .task, dueDate: "2026-10-02"),
            .init(title: "Today", category: "Thailand", kind: .memo, dueDate: "2026-10-05"),
            .init(title: "Today later", category: "Work", kind: .task, dueDate: "2026-10-05", dueTime: "18:05"),
            .init(title: "Inbox", category: "Inbox", kind: .task, dueDate: "2026-10-07"),
            .init(title: "Day 29", category: "Work", kind: .task, dueDate: "2026-11-03"),
        ])
    }

    @Test func capsOverdueAtTheMostRecentFiftyAndTheTotalAtTwoHundred() {
        let overdue: [ItemSnapshot] = (1...60).map { item("Overdue \($0)", in: work, on: -$0) }
        var coming: [ItemSnapshot] = []
        for offset in 0..<30 {
            for number in 0..<8 {
                coming.append(item("Day \(offset) #\(number)", in: work, on: offset, created: Double(number)))
            }
        }
        let snapshot = build(overdue + coming)
        #expect(snapshot.upcoming.count == 200)
        let overdueTitles = snapshot.upcoming.filter { $0.title.hasPrefix("Overdue") }.map(\.title)
        #expect(overdueTitles.count == 50)
        #expect(overdueTitles.first == "Overdue 50" && overdueTitles.last == "Overdue 1", "the most recent fifty, oldest first")
        #expect(snapshot.upcoming[50].title == "Day 0 #0", "then the nearest days")
    }

    @Test func clipsToTheWorkerLimitsBetweenCharacters() {
        let long = String(repeating: "א", count: 120)
        let emoji = String(repeating: "👩‍💻", count: 10) // 5 UTF-16 units each
        let snapshot = build(
            [item(String(repeating: "😀", count: 300), in: CategorySnapshot(id: work.id, name: long), on: 0)],
            categories: [CategorySnapshot(id: work.id, name: long, emoji: emoji)]
        )
        #expect(snapshot.categories[0].name.utf16.count == 100)
        #expect(snapshot.categories[0].emoji == String(repeating: "👩‍💻", count: 6))
        #expect(snapshot.upcoming[0].title.utf16.count == 500)
        #expect(snapshot.upcoming[0].title.allSatisfy { $0 == "😀" }, "no half emoji")
        #expect(snapshot.upcoming[0].category == snapshot.categories[0].name)
    }

    @Test func skipsBlankNamesAndTitles() {
        let blank = CategorySnapshot(name: "  ")
        let snapshot = build([item("   ", in: work, on: 0)], categories: [blank, work])
        #expect(snapshot.categories.map(\.name) == ["Work"])
        #expect(snapshot.upcoming.isEmpty)
    }

    @Test func aZoneWithoutAnIANANameIsSentAsUTC() {
        var custom = calendar
        custom.timeZone = TimeZone(secondsFromGMT: 3 * 3600 + 1800)!
        #expect(build([], calendar: custom).timeZone == "UTC")
    }

    @Test func encodesTheWorkersJSONShape() throws {
        let snapshot = build([item("Call Dan", in: work, on: 0, at: 9 * 60), item("Passport", .memo, in: thailand, on: 1)])
        let json = String(decoding: try MailboxSnapshot.encoder().encode(snapshot), as: UTF8.self)
        #expect(json.contains(#""updatedAt":"2026-10-05T07:00:00Z""#))
        #expect(json.contains(#"{"category":"Work","dueDate":"2026-10-05","dueTime":"09:00","kind":"task","title":"Call Dan"}"#))
        #expect(json.contains(#"{"category":"Thailand","dueDate":"2026-10-06","kind":"memo","title":"Passport"}"#), "no dueTime key without a time")
        #expect(json.contains(#""timeZone":"Asia\/Jerusalem""#) || json.contains(#""timeZone":"Asia/Jerusalem""#))
    }

    @Test func sameContentIgnoresWhenItWasBuilt() {
        var later = build([])
        later.updatedAt = now.addingTimeInterval(60)
        #expect(later.hasSameContent(as: build([])))
        later.categories.removeLast()
        #expect(!later.hasSameContent(as: build([])))
    }
}
