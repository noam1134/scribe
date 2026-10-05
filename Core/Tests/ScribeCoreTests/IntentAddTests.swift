import Foundation
import Testing
@testable import ScribeCore

/// Siri / Shortcuts adds (spec §8, §19): text + optional category → a draft
/// that always ends in a real category, or a question.
struct IntentAddTests {
    let calendar = TestCalendar.jerusalem
    let now = TestCalendar.monday // Mon 2026-10-05 10:00
    let categories = ParserFixture.categories
    let thailand = ParserFixture.thailand
    let work = ParserFixture.work

    func resolve(_ text: String, category: UUID? = nil, in categories: [CategorySnapshot]? = nil) -> IntentAdd.Resolution {
        IntentAdd.resolve(text, categoryID: category, categories: categories ?? self.categories, now: now, calendar: calendar)
    }

    // MARK: Resolve

    @Test func aTagPicksTheCategory() {
        let expected = ItemDraft(title: "book flights", categoryID: thailand.id, due: DueDate(day: LocalDay(2026, 10, 9)))
        #expect(resolve("book flights fri #thailand") == .ready(expected))
    }

    @Test func theCategoryParameterBeatsATag() {
        guard case .ready(let draft) = resolve("book flights #thailand", category: work.id) else {
            Issue.record("expected ready")
            return
        }
        #expect(draft.categoryID == work.id)
        #expect(draft.title == "book flights")
    }

    @Test func aDeletedCategoryParameterFallsBackToTheTag() {
        guard case .ready(let draft) = resolve("book flights #thai", category: UUID()) else {
            Issue.record("expected ready")
            return
        }
        #expect(draft.categoryID == thailand.id)
    }

    @Test func withoutATagItAsksForACategory() {
        let expected = ItemDraft(title: "call Dan", due: DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60))
        #expect(resolve("call Dan tomorrow 9am") == .needsCategory(expected))
    }

    @Test func anUnknownTagStaysInTheTitleAndItAsks() {
        #expect(resolve("buy milk #groceries") == .needsCategory(ItemDraft(title: "buy milk #groceries")))
    }

    @Test func theOnlyCategoryIsUsed() {
        #expect(resolve("buy milk", in: [work]) == .ready(ItemDraft(title: "buy milk", categoryID: work.id)))
    }

    @Test func withNoCategoriesThereIsNothingToFileInto() {
        #expect(resolve("buy milk #work", in: []) == .noCategories)
    }

    @Test(arguments: ["", "   ", "#work", "tomorrow", "!memo"])
    func anEmptyTitleAsksAgain(text: String) {
        #expect(resolve(text) == .emptyTitle)
    }

    @Test func theTextIsAskedForBeforeTheMissingCategories() {
        #expect(resolve("tomorrow", in: []) == .emptyTitle)
        #expect(resolve("#work", in: []) == .noCategories, "an unknown tag is a title")
    }

    @Test func memoMarkerMakesAMemo() {
        guard case .ready(let draft) = resolve("passport is in the drawer !memo #work") else {
            Issue.record("expected ready")
            return
        }
        #expect(draft.kind == .memo)
        #expect(draft.title == "passport is in the drawer")
    }

    @Test func hebrewWorks() {
        let expected = ItemDraft(title: "לקנות חלב", categoryID: ParserFixture.avoda.id, due: DueDate(day: LocalDay(2026, 10, 6)))
        #expect(resolve("לקנות חלב מחר #עבודה") == .ready(expected))
    }

    // MARK: Category search (Siri hears a name)

    @Test func searchRanksExactThenPrefixThenContains() {
        let work = CategorySnapshot(name: "Work", sortIndex: 2)
        let workout = CategorySnapshot(name: "Workout", sortIndex: 0)
        let homework = CategorySnapshot(name: "Homework", sortIndex: 1)
        let all = [workout, homework, work]
        #expect(IntentAdd.categories(matching: "work", in: all) == [work, workout, homework])
        #expect(IntentAdd.categories(matching: "  WORK ", in: all) == [work, workout, homework])
        #expect(IntentAdd.categories(matching: "out", in: all) == [workout])
        #expect(IntentAdd.categories(matching: "trip", in: all).isEmpty)
    }

    @Test func emptySearchListsEveryCategoryInOrder() {
        #expect(IntentAdd.categories(matching: " ", in: categories).map(\.name) == ["Thailand", "Work", "Bulgaria", "Budget", "עבודה"])
    }

    // MARK: Reply

    func reply(_ title: String, _ category: String, _ due: DueDate?, locale: String = "en_GB") -> String {
        IntentAdd.reply(title: title, categoryName: category, due: due, now: now, calendar: calendar, locale: Locale(identifier: locale))
    }

    @Test func replyWithoutADate() {
        #expect(reply("Buy milk", "Errands", nil) == "Added ‘Buy milk’ to Errands.")
    }

    @Test func replyNamesTheDayLikeSiriWould() {
        #expect(reply("Book flights", "Thailand", DueDate(day: LocalDay(2026, 10, 9))) == "Added ‘Book flights’ to Thailand, Friday.")
        #expect(reply("Pay rent", "Home", DueDate(day: LocalDay(2026, 10, 5))) == "Added ‘Pay rent’ to Home, today.")
        #expect(reply("Call Dan", "Work", DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60)) == "Added ‘Call Dan’ to Work, tomorrow at 09:00.")
        #expect(reply("Old", "Work", DueDate(day: LocalDay(2026, 10, 4))) == "Added ‘Old’ to Work, yesterday.")
    }

    @Test func replyUsesTheDateAWeekOrMoreAway() {
        #expect(reply("Dentist", "Home", DueDate(day: LocalDay(2026, 10, 12))) == "Added ‘Dentist’ to Home, 12 October.")
        #expect(reply("Dentist", "Home", DueDate(day: LocalDay(2026, 10, 12)), locale: "en_US") == "Added ‘Dentist’ to Home, October 12.")
        #expect(reply("Ski", "Bulgaria", DueDate(day: LocalDay(2027, 1, 3), minute: 7 * 60 + 30)) == "Added ‘Ski’ to Bulgaria, 3 January 2027 at 07:30.")
    }
}
