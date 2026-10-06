import Foundation
import Testing
@testable import ScribeCore

/// "Hey Siri, remind me in Scribe to …": plain language through the intent.
struct SmartIntentAddTests {
    let calendar = TestCalendar.jerusalem
    let now = TestCalendar.monday
    let categories = ParserFixture.categories
    let thailand = ParserFixture.thailand
    let work = ParserFixture.work

    func resolve(_ text: String, category: UUID? = nil) -> IntentAdd.Resolution {
        IntentAdd.resolve(text, categoryID: category, categories: categories, now: now, calendar: calendar)
    }

    @Test func aMentionFilesTheItem() {
        #expect(resolve("remind me to call the bank for work") == .ready(ItemDraft(title: "Call the bank", categoryID: work.id)))
        let hebrew = ItemDraft(title: "לשלוח את הדוח", categoryID: ParserFixture.avoda.id, due: DueDate(day: LocalDay(2026, 10, 6)))
        #expect(resolve("תזכיר לי לשלוח את הדוח לעבודה מחר") == .ready(hebrew))
    }

    @Test func theCategoryParameterBeatsAMentionWhichStaysInTheTitle() {
        #expect(resolve("call the bank for work", category: thailand.id) == .ready(ItemDraft(title: "call the bank for work", categoryID: thailand.id)))
        #expect(resolve("call the bank for work", category: work.id) == .ready(ItemDraft(title: "call the bank", categoryID: work.id)))
    }

    @Test func withoutAMentionItStillAsksWithACleanTitle() {
        let expected = ItemDraft(title: "Call Dan", due: DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60))
        #expect(resolve("remind me to call Dan tomorrow 9am") == .needsCategory(expected))
    }

    @Test func aTagStillWins() {
        #expect(resolve("fix the sink in Thailand #work") == .ready(ItemDraft(title: "fix the sink in Thailand", categoryID: work.id)))
    }
}
