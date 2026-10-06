import Foundation
import Testing
@testable import ScribeCore

/// Plain-language adds in the composer: the category a mention or the
/// on-device model works out is pre-picked; a tap, a `#tag` or the
/// context are never overridden by a guess.
@MainActor
struct SmartAddComposerTests {
    func make() throws -> (SwiftDataItemStore, QuickAddComposer) {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let composer = QuickAddComposer(store: store, calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"), now: { clock.now })
        return (store, composer)
    }

    // MARK: Mentions

    @Test func aMentionPrePicksAsYouType() throws {
        let (store, composer) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭"))
        try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "remind me to fix the dates for our hotels in Thai"
        #expect(composer.liveParse.categoryID == nil)
        composer.text = "remind me to fix the dates for our hotels in Thailand"
        let live = composer.liveParse
        #expect(live.categoryID == trip)
        #expect(live.categorySource == .mention)
        #expect(live.categoryIsGuess)
        #expect(live.canSave)
        #expect(live.suggestionRequest == nil, "nothing to ask the model")

        let id = try #require(try composer.save())
        let item = try #require(store.item(id))
        #expect(item.title == "Fix the dates for our hotels")
        #expect(item.categoryID == trip)
    }

    /// Tapping another category overrides the guess; the mention is then
    /// part of the title.
    @Test func aTapOverridesAMention() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand"))
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "remind me to fix the dates for our hotels in Thailand"
        composer.select(work)
        #expect(composer.liveParse.categorySource == .tapped)
        #expect(!composer.liveParse.categoryIsGuess)
        let item = try #require(try composer.save().flatMap(store.item))
        #expect(item.title == "Fix the dates for our hotels in Thailand")
        #expect(item.categoryID == work)
    }

    @Test func tappingTheMentionedCategoryKeepsTheTitleClean() throws {
        let (store, composer) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand"))
        composer.text = "book a hotel in Thailand"
        composer.select(trip)
        let item = try #require(try composer.save().flatMap(store.item))
        #expect(item.title == "book a hotel")
    }

    @Test func aTagBeatsAMention() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand"))
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "fix the sink in Thailand #work"
        #expect(composer.liveParse.categorySource == .tag)
        let item = try #require(try composer.save().flatMap(store.item))
        #expect(item.title == "fix the sink in Thailand")
        #expect(item.categoryID == work)
    }

    /// The words name a category on purpose; the screen's category is only
    /// where the composer was opened.
    @Test func aMentionBeatsTheContextDefault() throws {
        let (store, composer) = try make()
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.defaultCategoryID = home
        composer.text = "call the bank for work"
        #expect(composer.liveParse.categoryID == work)
        composer.text = "call the bank"
        #expect(composer.liveParse.categoryID == home)
        #expect(composer.liveParse.categorySource == .context)
        #expect(!composer.liveParse.categoryIsGuess)
    }

    @Test func datesStillParseAroundAMention() throws {
        let (store, composer) = try make()
        let family = try store.addCategory(CategoryDraft(name: "Family"))
        composer.text = "remind me to call mom tomorrow 9am for family"
        #expect(composer.chips.map(\.label) == ["Tomorrow", "09:00"])
        let item = try #require(try composer.save().flatMap(store.item))
        #expect(item.title == "Call mom")
        #expect(item.categoryID == family)
        #expect(item.due == DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60))
    }

    @Test func anUnknownTagKeepsTheMentionAndAsksNothing() throws {
        let (store, composer) = try make()
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "call the bank for work #wrok"
        #expect(composer.liveParse.categoryID == nil)
        #expect(composer.liveParse.suggestionRequest == nil)
        composer.select(home)
        let item = try #require(try composer.save().flatMap(store.item))
        #expect(item.title == "call the bank for work #wrok")
    }

    // MARK: The model's suggestion

    @Test func theModelIsAskedOnlyWhenNothingElsePicks() throws {
        let (store, composer) = try make()
        composer.text = "book the hotel"
        #expect(composer.liveParse.suggestionRequest == nil, "no categories to choose from")

        let trip = try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭"))
        try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "remind me to book the hotel tomorrow"
        let request = try #require(composer.liveParse.suggestionRequest)
        #expect(request.text == composer.text)
        #expect(request.title == "Book the hotel", "the parser's title, without the date")
        #expect(request.categoryNames == ["Thailand", "Work"])

        composer.text = ""
        #expect(composer.liveParse.suggestionRequest == nil, "no title")
        composer.text = "book the hotel #work"
        #expect(composer.liveParse.suggestionRequest == nil)
        composer.text = "book the hotel"
        composer.defaultCategoryID = trip
        #expect(composer.liveParse.suggestionRequest == nil)
        composer.defaultCategoryID = nil
        composer.select(trip)
        #expect(composer.liveParse.suggestionRequest == nil)
    }

    @Test func aSuggestionPrePicksAndCleansTheTitle() throws {
        let (store, composer) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand"))
        try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "book the hotel for bangkok"
        let request = try #require(composer.liveParse.suggestionRequest)
        composer.applySuggestion(categoryName: "Thailand", title: "Book the hotel", for: request)

        let live = composer.liveParse
        #expect(live.categoryID == trip)
        #expect(live.categorySource == .suggestion)
        #expect(live.categoryIsGuess)
        #expect(live.draft.title == "book the hotel", "the user's own spelling")
        #expect(live.suggestionRequest == request, "the same question: no new request")

        let item = try #require(try composer.save().flatMap(store.item))
        #expect(item.title == "book the hotel")
        #expect(item.categoryID == trip)
        #expect(composer.liveParse.categoryID == nil, "reset clears the suggestion")
    }

    @Test func aMadeUpCategoryOrTitleIsRefused() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand"))
        composer.text = "book the hotel"
        let request = try #require(composer.liveParse.suggestionRequest)
        composer.applySuggestion(categoryName: "Travel", title: "book the hotel", for: request)
        #expect(composer.liveParse.categoryID == nil)

        composer.applySuggestion(categoryName: "Thailand", title: "Reserve a room", for: request)
        #expect(composer.liveParse.categoryID != nil)
        #expect(composer.liveParse.draft.title == "book the hotel")

        composer.applySuggestion(categoryName: nil, title: nil, for: request)
        #expect(composer.liveParse.categoryID == nil, "\u{201C}none\u{201D} clears it")
    }

    /// An answer for text that has changed since is dropped; the last pick
    /// stays shown until the next answer, without its title.
    @Test func staleAnswersAreDroppedAndPicksStayWhileTyping() throws {
        let (store, composer) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand"))
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "book the hotel"
        let first = try #require(composer.liveParse.suggestionRequest)
        composer.text = "book the hotel near the beach"
        composer.applySuggestion(categoryName: "Work", title: nil, for: first)
        #expect(composer.liveParse.categoryID == nil)

        let second = try #require(composer.liveParse.suggestionRequest)
        composer.applySuggestion(categoryName: "Thailand", title: "book the hotel", for: second)
        #expect(composer.liveParse.categoryID == trip)
        composer.text = "book the hotel near the beach please"
        let live = composer.liveParse
        #expect(live.categoryID == trip)
        #expect(live.draft.title == "book the hotel near the beach please")
        #expect(live.suggestionRequest?.text == composer.text, "asks again for the new text")
        _ = work
    }

    @Test func aSuggestionNeverBeatsAStrongerPick() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand"))
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        composer.text = "call the bank"
        let request = try #require(composer.liveParse.suggestionRequest)
        composer.applySuggestion(categoryName: "Thailand", title: nil, for: request)
        composer.text = "call the bank for work"
        #expect(composer.liveParse.categoryID == work)
        #expect(composer.liveParse.categorySource == .mention)
    }

    @Test func clearingTheSuggestionUnpicks() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand"))
        composer.text = "book the hotel"
        let request = try #require(composer.liveParse.suggestionRequest)
        composer.applySuggestion(categoryName: "Thailand", title: nil, for: request)
        composer.clearSuggestion()
        #expect(composer.liveParse.categoryID == nil)
    }

    /// Saving before the model answers saves what's shown.
    @Test func savingBeforeAnAnswerSavesAsIs() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand"))
        composer.text = "book the hotel"
        #expect(try composer.save() == nil, "nothing picked yet: Add waits")
        #expect(composer.text == "book the hotel")
    }
}
