import Foundation
import Testing
@testable import ScribeCore

struct ParserCoreTests {
    typealias F = ParserFixture

    @Test func plainTextIsJustATitle() {
        let draft = F.parse("  buy   milk  ")
        #expect(draft.title == "buy milk")
        #expect(draft.kind == .task)
        #expect(draft.category == .none)
        #expect(draft.due == nil)
        #expect(draft.tokens.isEmpty)
        #expect(draft.isValid)
    }

    @Test func exactCategoryTagIgnoresCase() {
        let draft = F.parse("report #WORK")
        #expect(draft.title == "report")
        #expect(draft.category == .matched(F.work.id))
        #expect(draft.tokens == [RecognizedToken(kind: .category, text: "#WORK")])
    }

    @Test func prefixTagMatchesFirstInSortOrder() {
        #expect(F.parse("x #thai").category == .matched(F.thailand.id))
        #expect(F.parse("x #bu").category == .matched(F.bulgaria.id)) // Bulgaria sorts before Budget
        #expect(F.parse("x #bud").category == .matched(F.budget.id))
    }

    @Test func hebrewCategoryTag() {
        #expect(F.parse("דוח #עבודה").category == .matched(F.avoda.id))
    }

    @Test func unknownTagIsReportedNotCreated() {
        let draft = F.parse("report #zzz")
        #expect(draft.title == "report")
        #expect(draft.category == .unknown("zzz"))
        #expect(draft.itemDraft?.categoryID == nil)
    }

    @Test func loneHashIsText() {
        #expect(F.parse("issue #").title == "issue #")
    }

    @Test(arguments: ["!memo", "!note", "!פתק", "!MEMO"])
    func memoMarkers(marker: String) {
        let draft = F.parse("door code 4821 \(marker)")
        #expect(draft.kind == .memo)
        #expect(draft.title == "door code 4821")
    }

    @Test func tagOnlyInputIsInvalid() {
        let draft = F.parse("#work")
        #expect(draft.title == "")
        #expect(!draft.isValid)
        #expect(draft.itemDraft == nil)
    }

    @Test func onlyTrailingTokensCount() {
        let draft = F.parse("#work notes for the team")
        #expect(draft.title == "#work notes for the team")
        #expect(draft.category == .none)
    }

    @Test func eachKindIsUsedOnce() {
        let draft = F.parse("x #work #thailand")
        #expect(draft.category == .matched(F.thailand.id))
        #expect(draft.title == "x #work")
    }

    @Test func trailingPunctuationIsTolerated() {
        let draft = F.parse("call Dan #work.")
        #expect(draft.category == .matched(F.work.id))
        #expect(draft.title == "call Dan")
    }

    @Test func nonInteractiveKeepsUnknownTagInTitle() {
        let draft = F.parser.nonInteractiveDraft("pay rent #zzz", categories: F.categories, now: TestCalendar.monday)
        #expect(draft == ItemDraft(title: "pay rent #zzz"))
    }

    @Test func nonInteractiveUsesKnownTag() {
        let draft = F.parser.nonInteractiveDraft("report #work", categories: F.categories, now: TestCalendar.monday)
        #expect(draft == ItemDraft(title: "report", categoryID: F.work.id))
    }
}
