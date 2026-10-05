import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct QuickAddComposerTests {
    func make() throws -> (SwiftDataItemStore, QuickAddComposer) {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let composer = QuickAddComposer(store: store, calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"), now: { clock.now })
        return (store, composer)
    }

    @Test func chipsDescribeTheParse() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭"))
        composer.text = "book flights fri 18:00 #thai"
        #expect(composer.chips.map(\.label) == ["Fri 9 Oct", "18:00", "🇹🇭 Thailand"])
        #expect(composer.parsed.title == "book flights")
        #expect(composer.canSave)
    }

    @Test func tonightWithATimeShowsOneTimeChip() throws {
        let (_, composer) = try make()
        composer.text = "call Dan tonight at 9"
        #expect(composer.chips.map(\.label) == ["21:00"])
        composer.dismiss(try #require(composer.chips.first))
        #expect(composer.parsed.title == "call Dan tonight at 9")
        #expect(composer.chips.isEmpty)
    }

    @Test func dismissingAChipPutsItsTextBack() throws {
        let (_, composer) = try make()
        composer.text = "pay rent fri"
        composer.dismiss(try #require(composer.chips.first))
        #expect(composer.parsed.title == "pay rent fri")
        #expect(composer.parsed.due == nil)
    }

    @Test func savesWithParsedFieldsAndResets() throws {
        let (store, composer) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand"))
        composer.text = "book flights fri #thailand"
        let id = try #require(try composer.save())
        let item = try #require(store.item(id))
        #expect(item.title == "book flights")
        #expect(item.categoryID == trip)
        #expect(item.due == DueDate(day: LocalDay(2026, 10, 9)))
        #expect(composer.text.isEmpty)
    }

    @Test func unknownTagCanBecomeACategory() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Work", colorName: "red"))
        composer.text = "visa #bulgaria"
        #expect(composer.unknownCategoryName == "bulgaria")
        try composer.createUnknownCategory()
        #expect(store.categories.map(\.name) == ["Work", "bulgaria"])
        #expect(store.categories.last?.colorName == "orange")
        #expect(composer.unknownCategoryName == nil)
        let id = try #require(try composer.save())
        #expect(store.item(id)?.categoryID == store.categories.last?.id)
    }

    @Test func unknownTagLeftAloneStaysInTheTitle() throws {
        let (store, composer) = try make()
        composer.text = "buy milk #grocries"
        let id = try #require(try composer.save())
        #expect(store.item(id)?.title == "buy milk #grocries")
        #expect(store.item(id)?.categoryID == nil)
    }

    @Test func memoToggleAndDefaultCategory() throws {
        let (store, composer) = try make()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        composer.defaultCategoryID = work
        composer.isMemo = true
        composer.text = "door code 4821"
        let memo = try #require(try composer.save())
        #expect(store.item(memo)?.kind == .memo)
        #expect(store.item(memo)?.categoryID == work)
        #expect(composer.isMemo == false)

        composer.text = "fix sink #home" // an explicit tag beats the default
        let fix = try #require(try composer.save())
        #expect(store.item(fix)?.categoryID == home)
    }

    @Test func emptyTextCannotSave() throws {
        let (store, composer) = try make()
        composer.text = "   "
        #expect(!composer.canSave)
        #expect(try composer.save() == nil)
        #expect(store.items(.inbox).isEmpty)
    }
}
