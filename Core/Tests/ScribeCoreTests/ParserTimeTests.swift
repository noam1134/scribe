import Foundation
import Testing
@testable import ScribeCore

/// "Now" is Monday 2026-10-05 10:00 in Jerusalem.
struct ParserTimeTests {
    typealias F = ParserFixture

    static let timeCases: [(String, LocalDay, Int)] = [
        ("x 14:30", F.day(10, 5), 14 * 60 + 30),   // later today
        ("x 9:00", F.day(10, 6), 9 * 60),          // already passed → tomorrow
        ("x 10:00", F.day(10, 6), 10 * 60),        // exactly now → tomorrow
        ("x 9am", F.day(10, 6), 9 * 60),
        ("x 9 am", F.day(10, 6), 9 * 60),
        ("x 9:30pm", F.day(10, 5), 21 * 60 + 30),
        ("x 12pm", F.day(10, 5), 12 * 60),
        ("x 12am", F.day(10, 6), 0),
        ("x at 9", F.day(10, 6), 9 * 60),          // bare hour after "at" is 24-hour
        ("x at 14:30", F.day(10, 5), 14 * 60 + 30),
        ("x at 9 pm", F.day(10, 5), 21 * 60),
        ("x noon", F.day(10, 5), 12 * 60),
        ("x tonight", F.day(10, 5), 20 * 60),
    ]

    @Test(arguments: timeCases)
    func timesWithoutDate(text: String, day: LocalDay, minute: Int) {
        let draft = F.parse(text)
        #expect(draft.title == "x")
        #expect(draft.due == DueDate(day: day, minute: minute))
        #expect(draft.tokens.map(\.kind) == [.time])
    }

    @Test func tonightStaysTodayEvenWhenLate() {
        let draft = F.parse("x tonight", at: TestCalendar.date(2026, 10, 5, 22, 0))
        #expect(draft.due == DueDate(day: F.day(10, 5), minute: 20 * 60))
    }

    @Test func dateAndTimeTogether() {
        let expected = DueDate(day: F.day(10, 6), minute: 9 * 60)
        #expect(F.parse("call mom tomorrow 9am").due == expected)
        #expect(F.parse("call mom 9am tomorrow").due == expected)
        #expect(F.parse("call mom tomorrow at 9").due == expected)
        #expect(F.parse("call mom tomorrow at 9").title == "call mom")
        #expect(F.parse("party fri tonight").due == DueDate(day: F.day(10, 9), minute: 20 * 60))
    }

    @Test(arguments: ["room 9", "x 25:00", "x 9:5", "x 13pm", "x 0am", "x 9:60", "x at", "x at 1 2", "x 9 : 30"])
    func nonTimesStayInTitle(text: String) {
        let draft = F.parse(text)
        #expect(draft.title == text)
        #expect(draft.due == nil)
    }

    @Test func fullExample() {
        let draft = F.parse("Book flights fri 18:00 #thai !memo")
        #expect(draft.title == "Book flights")
        #expect(draft.kind == .memo)
        #expect(draft.category == .matched(F.thailand.id))
        #expect(draft.due == DueDate(day: F.day(10, 9), minute: 18 * 60))
        #expect(draft.tokens.map(\.kind) == [.date, .time, .category, .kind])
    }

    @Test func spacesNeverMergeNumbers() {
        let afternoon = F.parse("room 1 2:30pm")
        #expect(afternoon.title == "room 1")
        #expect(afternoon.due == DueDate(day: F.day(10, 5), minute: 14 * 60 + 30))
        let morning = F.parse("take 1 9:30")
        #expect(morning.title == "take 1")
        #expect(morning.due == DueDate(day: F.day(10, 6), minute: 9 * 60 + 30))
    }

    @Test func atNoonKeepsTheDate() {
        let draft = F.parse("call tomorrow at noon")
        #expect(draft.title == "call")
        #expect(draft.due == DueDate(day: F.day(10, 6), minute: 12 * 60))
        #expect(F.parse("lunch at noon").due == DueDate(day: F.day(10, 5), minute: 12 * 60))
    }
}
