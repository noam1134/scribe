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

    /// The category isn't a chip: the sheet's category row shows it.
    @Test func chipsDescribeTheParse() throws {
        let (store, composer) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭"))
        composer.text = "book flights fri 18:00 #thai"
        #expect(composer.chips.map(\.label) == ["Fri 9 Oct", "18:00"])
        #expect(composer.parsed.title == "book flights")
        #expect(composer.liveParse.categoryID == trip)
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
        #expect(!composer.canSave)
        try composer.createUnknownCategory()
        #expect(store.categories.map(\.name) == ["Work", "bulgaria"])
        #expect(store.categories.last?.colorName == "orange")
        #expect(composer.unknownCategoryName == nil)
        #expect(composer.selectedCategoryID == store.categories.last?.id)
        let id = try #require(try composer.save())
        #expect(store.item(id)?.categoryID == store.categories.last?.id)
        #expect(store.item(id)?.title == "visa")
    }

    /// A tag that matches nothing doesn't pick a category, so Add waits; a
    /// picked category files it, keeping the unrecognized tag in the title.
    @Test func unknownTagLeftAloneStaysInTheTitle() throws {
        let (store, composer) = try make()
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        composer.text = "buy milk #grocries"
        #expect(!composer.canSave)
        #expect(try composer.save() == nil)
        composer.select(home)
        let id = try #require(try composer.save())
        #expect(store.item(id)?.title == "buy milk #grocries")
        #expect(store.item(id)?.categoryID == home)
    }

    /// Nothing lands in the Inbox from the composer: with no tag, no default
    /// and no pick, Add waits and the text stays.
    @Test func addWaitsForACategory() throws {
        let (store, composer) = try make()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "call Dan tomorrow"
        #expect(composer.parsed.isValid)
        #expect(composer.liveParse.categoryID == nil)
        #expect(!composer.canSave)
        #expect(try composer.save() == nil)
        #expect(composer.text == "call Dan tomorrow")
        #expect(store.items(.inbox).isEmpty)

        composer.select(work)
        #expect(composer.canSave)
        let id = try #require(try composer.save())
        #expect(store.item(id)?.categoryID == work)
        #expect(composer.selectedCategoryID == nil) // reset after saving
    }

    /// Tapping a category chip beats a typed tag; the tag text still leaves the title.
    @Test func aTappedCategoryBeatsATypedTag() throws {
        let (store, composer) = try make()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        try store.addCategory(CategoryDraft(name: "Home"))
        composer.text = "fix sink #home"
        composer.select(work)
        #expect(composer.liveParse.categoryID == work)
        let id = try #require(try composer.save())
        #expect(store.item(id)?.categoryID == work)
        #expect(store.item(id)?.title == "fix sink")
    }

    /// A picked category that gets deleted (e.g. by sync) no longer counts.
    @Test func aDeletedPickIsIgnored() throws {
        let (store, composer) = try make()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "send invoice"
        composer.select(work)
        try store.deleteCategory(work)
        #expect(composer.liveParse.categoryID == nil)
        #expect(!composer.canSave)
    }

    /// The row lists every category, from the same read as the parse.
    @Test func liveParseListsTheCategoriesForTheRow() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Work"))
        try store.addCategory(CategoryDraft(name: "Home"))
        #expect(composer.liveParse.categories == store.categories)
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

    /// An add link or the on-screen category can name a category that was
    /// deleted (here or by sync) or never existed: nothing is preselected,
    /// so Add waits for a pick instead of failing or filing to the Inbox.
    @Test func aMissingDefaultCategoryLeavesNothingSelected() throws {
        let (store, composer) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand"))
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.defaultCategoryID = trip
        try store.deleteCategory(trip)
        composer.text = "book flights"
        #expect(composer.liveParse.categoryID == nil)
        #expect(try composer.save() == nil)
        #expect(composer.text == "book flights")

        composer.defaultCategoryID = UUID()
        #expect(!composer.canSave)
        composer.select(work)
        let flights = try #require(try composer.save())
        #expect(store.item(flights)?.categoryID == work)
    }

    @Test func unknownTagFilesToTheDefaultCategoryAndStaysInTheTitle() throws {
        let (store, composer) = try make()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.defaultCategoryID = work
        composer.text = "buy milk #grocries"
        let id = try #require(try composer.save())
        #expect(store.item(id)?.title == "buy milk #grocries")
        #expect(store.item(id)?.categoryID == work)
    }

    nonisolated static let liveParseTexts: [String] = [
        "",
        "book flights fri 18:00 #thai",
        "call Dan tonight at 9",
        "visa #bulgaria",
        "door code 4821 !memo",
    ]

    /// The sheet reads `liveParse` once per render; it must say exactly
    /// what the separate properties say, before and after a chip is dismissed.
    @Test(arguments: liveParseTexts)
    func liveParseAgreesWithTheSeparateProperties(text: String) throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭"))
        composer.text = text
        func expectAgreement() {
            let live = composer.liveParse
            #expect(live.draft == composer.parsed)
            #expect(live.chips == composer.chips)
            #expect(live.canSave == composer.canSave)
            #expect(live.unknownCategoryName == composer.unknownCategoryName)
        }
        expectAgreement()
        if let first = composer.chips.first {
            composer.dismiss(first)
            expectAgreement()
        }
    }

    @Test func emptyTextCannotSave() throws {
        let (store, composer) = try make()
        composer.text = "   "
        #expect(!composer.canSave)
        #expect(try composer.save() == nil)
        #expect(store.items(.inbox).isEmpty)
    }

    // MARK: Notes

    @Test func notesBecomeTheBodyAndAreCleared() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand"))
        composer.text = "book flights fri #thailand"
        composer.notes = "Window seat\nMorning flight"
        let id = try #require(try composer.save())
        let item = try #require(store.item(id))
        #expect(item.title == "book flights")
        #expect(item.body == "Window seat\nMorning flight")
        #expect(item.kind == .task)
        #expect(composer.notes.isEmpty)
    }

    @Test func memoKeepsItsNotes() throws {
        let (store, composer) = try make()
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        composer.defaultCategoryID = home
        composer.isMemo = true
        composer.text = "wifi password"
        composer.notes = "hunter2"
        let item = try #require(try composer.save().flatMap(store.item))
        #expect(item.kind == .memo)
        #expect(item.body == "hunter2")
    }

    /// Only the surrounding blank lines and spaces go; the user's own line
    /// breaks stay. Notes are never parsed.
    @Test func notesAreTrimmedNotParsed() throws {
        let (store, composer) = try make()
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        composer.defaultCategoryID = home
        composer.text = "pack"
        composer.notes = "\n  passport\n\ncharger tomorrow #work  \n"
        let item = try #require(try composer.save().flatMap(store.item))
        #expect(item.body == "passport\n\ncharger tomorrow #work")
        #expect(item.due == nil)
        #expect(composer.liveParse.chips.isEmpty)
    }

    @Test func notesAloneCannotSaveAndAreKept() throws {
        let (store, composer) = try make()
        composer.defaultCategoryID = try store.addCategory(CategoryDraft(name: "Home"))
        composer.notes = "just notes"
        #expect(!composer.canSave)
        #expect(try composer.save() == nil)
        #expect(composer.notes == "just notes")
    }

    @Test func resetClearsNotes() throws {
        let (_, composer) = try make()
        composer.text = "x"
        composer.notes = "y"
        composer.reset()
        #expect(composer.text.isEmpty)
        #expect(composer.notes.isEmpty)
    }
}
