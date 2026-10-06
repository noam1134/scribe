import Foundation
import Testing
@testable import ScribeCore

/// The on-device model's answer is checked before anything is filed: the
/// category must be one of the user's, the title a fair cut of theirs.
struct CategorySuggestionTests {
    let thailand = CategorySnapshot(name: "Thailand")
    let work = CategorySnapshot(name: "Work")
    var categories: [CategorySnapshot] { [thailand, work] }

    func check(_ name: String?, title: String? = nil, for original: String = "book the hotel for bangkok", in categories: [CategorySnapshot]? = nil) -> CategorySuggestion? {
        CategorySuggestion.checked(categoryName: name, suggestedTitle: title, for: original, categories: categories ?? self.categories)
    }

    @Test func theNameMustBeACategory() {
        #expect(check("Thailand")?.categoryID == thailand.id)
        #expect(check(" thailand ")?.categoryID == thailand.id, "case and spaces don't matter")
        #expect(check("Travel") == nil)
        #expect(check("none") == nil)
        #expect(check("") == nil)
        #expect(check(nil) == nil)
    }

    @Test func emojiNamesMatchTheirPlainName() {
        let flagged = CategorySnapshot(name: "🇹🇭 Thailand")
        #expect(check("Thailand", in: [flagged])?.categoryID == flagged.id)
        #expect(check("🇹🇭 Thailand", in: [flagged])?.categoryID == flagged.id)
    }

    @Test func twoCategoriesWithTheAnsweredNameAreAmbiguous() {
        let twins = [CategorySnapshot(name: "Work 💼"), CategorySnapshot(name: "💼 Work")]
        #expect(check("work", in: twins) == nil)
    }

    @Test func aCutOfTheTitleIsKeptInTheUsersSpelling() {
        #expect(check("Thailand", title: "Book the hotel")?.title == "book the hotel")
        #expect(check("Thailand", title: "book the hotel.")?.title == "book the hotel")
        #expect(check("Work", title: "call the bank", for: "could you call the bank")?.title == "Call the bank")
    }

    /// Without a usable title the original stays.
    static let refusedTitles: [String?] = [
        nil,
        "",
        "Reserve a room",          // rewritten
        "hotel",                   // under half the words
        "ook the hotel",           // not on word boundaries
    ]

    @Test(arguments: refusedTitles)
    func otherTitlesKeepTheOriginal(title: String?) {
        #expect(check("Thailand", title: title)?.title == "book the hotel for bangkok")
    }

    @Test func hebrewCuts() {
        let avoda = CategorySnapshot(name: "עבודה")
        let checked = CategorySuggestion.checked(categoryName: "עבודה", suggestedTitle: "לשלוח את הדוח", for: "לשלוח את הדוח לבוס", categories: [avoda])
        #expect(checked == CategorySuggestion(categoryID: avoda.id, title: "לשלוח את הדוח"))
    }
}
