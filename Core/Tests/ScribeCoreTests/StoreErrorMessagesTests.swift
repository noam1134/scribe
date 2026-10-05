import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct StoreErrorMessagesTests {
    @Test func duplicateNameReadsAsASentence() throws {
        let store = try makeStore()
        try store.addCategory(CategoryDraft(name: "Work"))
        let error = #expect(throws: StoreError.duplicateCategoryName) {
            try store.addCategory(CategoryDraft(name: "work"))
        }
        #expect(error?.localizedDescription == "There's already a category with that name.")
    }

    @Test func everyErrorHasAMessage() {
        let errors: [StoreError] = [
            .emptyTitle, .emptyCategoryName, .duplicateCategoryName,
            .invalidColorName("beige"), .itemNotFound(UUID()), .categoryNotFound(UUID()),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(!error.localizedDescription.contains("ScribeCore"))
        }
    }
}
