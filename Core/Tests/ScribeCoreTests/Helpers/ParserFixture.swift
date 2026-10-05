import Foundation
@testable import ScribeCore

enum ParserFixture {
    static let thailand = CategorySnapshot(name: "Thailand", sortIndex: 0)
    static let work = CategorySnapshot(name: "Work", sortIndex: 1)
    static let bulgaria = CategorySnapshot(name: "Bulgaria", sortIndex: 2)
    static let budget = CategorySnapshot(name: "Budget", sortIndex: 3)
    static let avoda = CategorySnapshot(name: "עבודה", sortIndex: 4)
    static let categories = [work, budget, thailand, bulgaria, avoda] // deliberately not in sortIndex order

    static let parser = QuickAddParser(calendar: TestCalendar.jerusalem)

    /// Parses at Monday 2026-10-05 10:00 Jerusalem unless told otherwise.
    static func parse(_ text: String, at now: Date = TestCalendar.monday, disabled: Set<TokenKind> = [], parser: QuickAddParser = parser) -> ParsedDraft {
        parser.parse(text, categories: categories, now: now, disabled: disabled)
    }

    static func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> LocalDay {
        LocalDay(year, month, day)
    }
}
