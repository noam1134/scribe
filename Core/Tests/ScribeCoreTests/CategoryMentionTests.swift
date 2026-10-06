import Foundation
import Testing
@testable import ScribeCore

/// Plain-language quick-add: a category named at the end of the text
/// ("… in Thailand", "… לעבודה") files the item there and leaves the title.
struct CategoryMentionTests {
    typealias F = ParserFixture

    static let family = CategorySnapshot(name: "Family", sortIndex: 10)
    static let home = CategorySnapshot(name: "הבית", sortIndex: 11)
    static let thai = CategorySnapshot(name: "תאילנד", sortIndex: 12)
    static let categories = F.categories + [family, home, thai]

    func parse(_ text: String, in categories: [CategorySnapshot] = Self.categories) -> ParsedDraft {
        F.parser.parse(text, categories: categories, now: TestCalendar.monday)
    }

    static let englishCases: [(String, String, UUID)] = [
        ("remind me to fix the dates for our hotels in Thailand", "Fix the dates for our hotels", F.thailand.id),
        ("call the bank for work", "call the bank", F.work.id),
        ("book a hotel to my Thailand list", "book a hotel", F.thailand.id),
        ("send the report on the Work list", "send the report", F.work.id),
        ("pay the invoice in the work category", "pay the invoice", F.work.id),
        ("call the embassy for my Bulgaria list", "call the embassy", F.bulgaria.id),
        ("book a hotel in THAILAND", "book a hotel", F.thailand.id),
        ("book a hotel in Thailand.", "book a hotel", F.thailand.id),
        ("call mom for family", "call mom", family.id),
    ]

    @Test(arguments: englishCases)
    func englishMentionsFileTheItem(text: String, title: String, category: UUID) {
        let draft = parse(text)
        #expect(draft.title == title)
        #expect(draft.mentionedCategoryID == category)
        #expect(draft.category == CategoryMatch.none)
        #expect(draft.itemDraft?.categoryID == category)
        #expect(draft.tokens.map(\.kind) == [.mention])
    }

    static let hebrewCases: [(String, String, UUID)] = [
        ("לשלוח את הדוח לעבודה", "לשלוח את הדוח", F.avoda.id),
        ("תזכיר לי לשלוח את הדוח לעבודה", "לשלוח את הדוח", F.avoda.id),
        ("לבדוק מלונות בתאילנד", "לבדוק מלונות", thai.id),
        ("לבדוק מלונות ב-תאילנד", "לבדוק מלונות", thai.id),
        ("לקנות מתנה ברשימת עבודה", "לקנות מתנה", F.avoda.id),
        ("לקנות מתנה לרשימה של עבודה", "לקנות מתנה", F.avoda.id),
        // ב/ל swallow the article: "בבית" is in "הבית".
        ("לנקות את המטבח בבית", "לנקות את המטבח", home.id),
        ("לשלוח מייל לThailand", "לשלוח מייל", F.thailand.id),
    ]

    @Test(arguments: hebrewCases)
    func hebrewMentionsFileTheItem(text: String, title: String, category: UUID) {
        let draft = parse(text)
        #expect(draft.title == title)
        #expect(draft.mentionedCategoryID == category)
    }

    /// Words that aren't a filing stay in the title.
    static let notMentions: [String] = [
        "book flights to Thailand",       // a destination: "to" needs "… list"
        "Thailand visa",                  // no preposition
        "call the bank for homework",     // not a whole word of "Work"
        "work in progress",               // not at the end
        "בית ספר",                        // no ב/ל
        "לעבוד",                          // not the name
    ]

    @Test(arguments: notMentions)
    func otherWordsStayInTheTitle(text: String) {
        let draft = parse(text)
        #expect(draft.title == text)
        #expect(draft.mentionedCategoryID == nil)
    }

    @Test func datesAroundTheMentionStillParse() {
        let after = parse("remind me to call mom tomorrow 9am for family")
        #expect(after.title == "Call mom")
        #expect(after.mentionedCategoryID == Self.family.id)
        #expect(after.due == DueDate(day: F.day(10, 6), minute: 9 * 60))

        let before = parse("call mom for family tomorrow 9am")
        #expect(before.title == "call mom")
        #expect(before.mentionedCategoryID == Self.family.id)
        #expect(before.due == DueDate(day: F.day(10, 6), minute: 9 * 60))

        let hebrew = parse("לשלוח את הדוח לעבודה מחר")
        #expect(hebrew.title == "לשלוח את הדוח")
        #expect(hebrew.mentionedCategoryID == F.avoda.id)
        #expect(hebrew.due == DueDate(day: F.day(10, 6)))
    }

    // MARK: Matching names

    @Test func emojiInTheNameOrTheTextIsIgnored() {
        let flagged = CategorySnapshot(name: "🇹🇭 Thailand", emoji: "🌴")
        #expect(parse("book a hotel in Thailand", in: [flagged]).mentionedCategoryID == flagged.id)
        #expect(parse("book a hotel in 🇹🇭 Thailand", in: [flagged]).mentionedCategoryID == flagged.id)
        let work = CategorySnapshot(name: "Work 💼")
        #expect(parse("call the bank for work", in: [work]).mentionedCategoryID == work.id)
    }

    @Test func diacriticsAreIgnored() {
        let cafe = CategorySnapshot(name: "Café")
        #expect(parse("order beans for cafe", in: [cafe]).mentionedCategoryID == cafe.id)
    }

    @Test func aWholeWordOfALongerNameMatches() {
        let projects = CategorySnapshot(name: "Work Projects")
        let draft = parse("call the client for work", in: [projects])
        #expect(draft.mentionedCategoryID == projects.id)
        #expect(draft.title == "call the client")
        #expect(parse("call the client for work projects", in: [projects]).title == "call the client")
    }

    @Test func theWholeNameBeatsPartOfAnother() {
        let work = CategorySnapshot(name: "Work")
        let projects = CategorySnapshot(name: "Work Projects")
        #expect(parse("call the client for work", in: [projects, work]).mentionedCategoryID == work.id)
    }

    @Test func anAmbiguousMentionPicksNothing() {
        let projects = CategorySnapshot(name: "Work Projects")
        let admin = CategorySnapshot(name: "Work Admin")
        let draft = parse("call the client for work", in: [projects, admin])
        #expect(draft.mentionedCategoryID == nil)
        #expect(draft.title == "call the client for work")

        let twins = [CategorySnapshot(name: "Work"), CategorySnapshot(name: "💼 Work")]
        #expect(parse("call the client for work", in: twins).mentionedCategoryID == nil)
    }

    @Test func aHebrewPrefixNeedsTheWholeName() {
        let school = CategorySnapshot(name: "בית ספר")
        #expect(parse("לקנות מחברות לבית ספר", in: [school]).mentionedCategoryID == school.id)
        #expect(parse("אני רוצה לספר", in: [school]).mentionedCategoryID == nil)
    }

    // MARK: Against a tag

    /// An explicit `#tag` wins; the mention is then just words.
    @Test func aTagBeatsAMention() {
        let draft = parse("fix the sink in Thailand #work")
        #expect(draft.category == .matched(F.work.id))
        #expect(draft.mentionedCategoryID == nil)
        #expect(draft.title == "fix the sink in Thailand")
        #expect(draft.itemDraft?.categoryID == F.work.id)

        let tagFirst = parse("fix the sink #work in Thailand")
        #expect(tagFirst.title == "fix the sink in Thailand")
        #expect(tagFirst.category == .matched(F.work.id))
    }

    @Test func anUnknownTagAlsoKeepsTheMentionInTheTitle() {
        let draft = parse("call the bank for work #wrok")
        #expect(draft.category == .unknown("wrok"))
        #expect(draft.mentionedCategoryID == nil)
        #expect(draft.title == "call the bank for work")
    }

    @Test func aTagForTheSameCategoryLeavesTheMention() {
        let draft = parse("book a hotel in Thailand #thailand")
        #expect(draft.title == "book a hotel")
        #expect(draft.category == .matched(F.thailand.id))
        #expect(draft.mentionedCategoryID == F.thailand.id)
    }

    // MARK: The title

    /// A mention never takes the whole title.
    @Test(arguments: ["for work", "remind me for work", "in Thailand"])
    func aMentionLeavesATitle(text: String) {
        let draft = parse(text)
        #expect(draft.mentionedCategoryID == nil)
        #expect(draft.isValid)
    }

    @Test func aMentionThatWouldLeaveOnlyADateStays() {
        let draft = parse("tomorrow for work")
        #expect(draft.mentionedCategoryID == nil)
        #expect(draft.isValid)
    }

    @Test func aDisabledMentionGoesBackIntoTheTitle() {
        let draft = F.parser.parse("call the bank for work tomorrow", categories: Self.categories, now: TestCalendar.monday, disabled: [.mention])
        #expect(draft.title == "call the bank for work")
        #expect(draft.mentionedCategoryID == nil)
        #expect(draft.due == DueDate(day: F.day(10, 6)))
    }
}
