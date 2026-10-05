import Foundation
import Testing
@testable import ScribeCore

/// "Now" is Monday 2026-10-05 10:00 in Jerusalem.
struct ParserHebrewTests {
    typealias F = ParserFixture

    static let dateCases: [(String, LocalDay)] = [
        ("לקנות חלב היום", F.day(10, 5)),
        ("לקנות חלב מחר", F.day(10, 6)),
        ("לקנות חלב מחרתיים", F.day(10, 7)),
        ("לקנות חלב שישי", F.day(10, 9)),
        ("לקנות חלב יום שישי", F.day(10, 9)),
        ("לקנות חלב ביום שישי", F.day(10, 9)),
        ("לקנות חלב בשישי", F.day(10, 9)),
        ("לקנות חלב שבת", F.day(10, 10)),
        ("לקנות חלב בשבת", F.day(10, 10)),
        ("לקנות חלב ראשון", F.day(10, 11)),
        ("לקנות חלב שני", F.day(10, 12)),          // today is Monday → next Monday
        ("לקנות חלב שבוע הבא", F.day(10, 11)),
        ("לקנות חלב בשבוע הבא", F.day(10, 11)),
        ("לקנות חלב בעוד 3 ימים", F.day(10, 8)),
        ("לקנות חלב בעוד יום", F.day(10, 6)),
        ("לקנות חלב בעוד יומיים", F.day(10, 7)),
        ("לקנות חלב בעוד שבוע", F.day(10, 12)),
        ("לקנות חלב בעוד שבועיים", F.day(10, 19)),
        ("לקנות חלב בעוד 2 שבועות", F.day(10, 19)),
        ("לקנות חלב 12/10", F.day(10, 12)),
    ]

    @Test(arguments: dateCases)
    func hebrewDates(text: String, expected: LocalDay) {
        let draft = F.parse(text)
        #expect(draft.title == "לקנות חלב")
        #expect(draft.due == DueDate(day: expected))
    }

    static let timeCases: [(String, LocalDay, Int)] = [
        ("פגישה ב-9", F.day(10, 6), 9 * 60),
        ("פגישה ב9", F.day(10, 6), 9 * 60),
        ("פגישה ב-14:00", F.day(10, 5), 14 * 60),
        ("פגישה ב9:30", F.day(10, 6), 9 * 60 + 30),
        ("פגישה בשעה 14:00", F.day(10, 5), 14 * 60),
        ("פגישה בשעה 9", F.day(10, 6), 9 * 60),
        ("פגישה בצהריים", F.day(10, 5), 12 * 60),
        ("פגישה הערב", F.day(10, 5), 20 * 60),
        ("פגישה מחר ב-9", F.day(10, 6), 9 * 60),
        ("פגישה ביום שישי בשעה 18:00", F.day(10, 9), 18 * 60),
    ]

    @Test(arguments: timeCases)
    func hebrewTimes(text: String, day: LocalDay, minute: Int) {
        let draft = F.parse(text)
        #expect(draft.title == "פגישה")
        #expect(draft.due == DueDate(day: day, minute: minute))
    }

    @Test func shabbatInsideTitleIsNotADate() {
        let draft = F.parse("ארוחת שבת עם המשפחה")
        #expect(draft.title == "ארוחת שבת עם המשפחה")
        #expect(draft.due == nil)
    }

    @Test func hebrewMemoWithCategoryAndDate() {
        let draft = F.parse("קוד לדלת 4821 #עבודה מחר !פתק")
        #expect(draft.title == "קוד לדלת 4821")
        #expect(draft.kind == .memo)
        #expect(draft.category == .matched(F.avoda.id))
        #expect(draft.due == DueDate(day: F.day(10, 6)))
    }

    @Test func mixedLanguages() {
        #expect(F.parse("לקנות חלב tomorrow").due == DueDate(day: F.day(10, 6)))
        #expect(F.parse("buy milk מחר").due == DueDate(day: F.day(10, 6)))
        #expect(F.parse("buy milk מחר").title == "buy milk")
    }
}
