import Foundation
import Testing
@testable import ScribeCore

/// "Now" is Monday 2026-10-05 10:00 in Jerusalem.
struct ParserDateTests {
    typealias F = ParserFixture

    static let englishCases: [(String, LocalDay)] = [
        ("x today", F.day(10, 5)),
        ("x tomorrow", F.day(10, 6)),
        ("x tmr", F.day(10, 6)),
        ("x tmrw", F.day(10, 6)),
        ("x Tomorrow", F.day(10, 6)),
        ("x tomorrow.", F.day(10, 6)),
        ("x tue", F.day(10, 6)),
        ("x friday", F.day(10, 9)),
        ("x fri,", F.day(10, 9)),
        ("x sun", F.day(10, 11)),
        ("x mon", F.day(10, 12)),        // today is Monday: means NEXT Monday
        ("x next mon", F.day(10, 12)),
        ("x next fri", F.day(10, 9)),    // "next fri" == "fri"
        ("x next week", F.day(10, 11)),  // next Sunday
        ("x in 3 days", F.day(10, 8)),
        ("x in 1 day", F.day(10, 6)),
        ("x in 2 weeks", F.day(10, 19)),
        ("x 12/10", F.day(10, 12)),      // day/month
        ("x 12.10", F.day(10, 12)),
        ("x 5/10", F.day(10, 5)),        // today
        ("x 1/10", F.day(10, 1, 2027)),  // already passed → next year
        ("x 12/10/27", F.day(10, 12, 2027)),
        ("x 12/10/2027", F.day(10, 12, 2027)),
        ("x oct 12", F.day(10, 12)),
        ("x 12 oct", F.day(10, 12)),
        ("x October 12", F.day(10, 12)),
        ("x jan 3", F.day(1, 3, 2027)),
    ]

    @Test(arguments: englishCases)
    func englishDates(text: String, expected: LocalDay) {
        let draft = F.parse(text)
        #expect(draft.title == "x")
        #expect(draft.due == DueDate(day: expected))
        #expect(draft.tokens.map(\.kind) == [.date])
    }

    @Test(arguments: ["x 31/02", "x 12/13", "x 1.5.6.7", "x in 0 days", "x 12/10/202", "x oct 40"])
    func impossibleDatesStayInTitle(text: String) {
        let draft = F.parse(text)
        #expect(draft.title == text)
        #expect(draft.due == nil)
    }

    @Test func weekdayInsideTitleIsNotADate() {
        let draft = F.parse("fri night plans with Dan")
        #expect(draft.title == "fri night plans with Dan")
        #expect(draft.due == nil)
    }

    @Test func dateAndTagInAnyOrder() {
        for text in ["book flights fri #thailand", "book flights #thailand fri"] {
            let draft = F.parse(text)
            #expect(draft.title == "book flights")
            #expect(draft.due == DueDate(day: F.day(10, 9)))
            #expect(draft.category == .matched(F.thailand.id))
        }
        #expect(F.parse("book flights fri #thailand").tokens == [
            RecognizedToken(kind: .date, text: "fri"),
            RecognizedToken(kind: .category, text: "#thailand"),
        ])
    }

    @Test func secondDateStopsTheScan() {
        let draft = F.parse("x tomorrow fri")
        #expect(draft.title == "x tomorrow")
        #expect(draft.due == DueDate(day: F.day(10, 9)))
    }

    @Test func disablingDateKeepsItsTextInTitle() {
        let draft = F.parse("book flights fri #thailand", disabled: [.date])
        #expect(draft.title == "book flights fri")
        #expect(draft.due == nil)
        #expect(draft.category == .matched(F.thailand.id))
        #expect(draft.tokens.map(\.kind) == [.category])
    }

    @Test func disablingCategoryKeepsItsTextInTitle() {
        let draft = F.parse("book flights fri #thailand", disabled: [.category])
        #expect(draft.title == "book flights #thailand")
        #expect(draft.due == DueDate(day: F.day(10, 9)))
        #expect(draft.category == .none)
    }

    @Test func tomorrowOnNewYearsEveRollsTheYear() {
        let draft = F.parse("x tomorrow", at: TestCalendar.date(2026, 12, 31, 18, 0))
        #expect(draft.due == DueDate(day: LocalDay(2027, 1, 1)))
    }

    @Test func nextWeekFollowsTheDevicesFirstWeekday() {
        let mondayFirst = QuickAddParser(calendar: TestCalendar.make(timeZone: "Asia/Jerusalem", firstWeekday: 2))
        #expect(F.parse("x next week", parser: mondayFirst).due == DueDate(day: F.day(10, 12)))
    }

    static let leadInCases: [(String, String, LocalDay)] = [
        ("dinner with Dan on friday", "dinner with Dan", F.day(10, 9)),
        ("meeting this friday", "meeting", F.day(10, 9)),
        ("submit report by fri", "submit report", F.day(10, 9)),
        ("pay rent on 12/10", "pay rent", F.day(10, 12)),
        ("call back by tomorrow", "call back", F.day(10, 6)),
        ("visa on oct 12", "visa", F.day(10, 12)),
    ]

    @Test(arguments: leadInCases)
    func englishLeadInsBeforeADate(text: String, title: String, day: LocalDay) {
        let draft = F.parse(text)
        #expect(draft.title == title)
        #expect(draft.due == DueDate(day: day))
    }
}
