import Foundation
import SwiftData
import Testing
@testable import ScribeCore

@MainActor
struct StoreCategoryTests {
    @Test func addCategoriesAppendInOrder() throws {
        let store = try makeStore()
        let work = try store.addCategory(CategoryDraft(name: " Work ", emoji: "💼", colorName: "indigo"))
        let thailand = try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭", colorName: "green"))
        #expect(store.categories.map(\.id) == [work, thailand])
        let first = store.categories[0]
        #expect(first.name == "Work")
        #expect(first.emoji == "💼")
        #expect(first.colorName == "indigo")
        #expect(first.sortIndex == 0)
        #expect(store.categories[1].sortIndex == 1)
    }

    @Test func rejectsBlankDuplicateAndBadColor() throws {
        let store = try makeStore()
        try store.addCategory(CategoryDraft(name: "Thailand"))
        #expect(throws: StoreError.emptyCategoryName) { try store.addCategory(CategoryDraft(name: "  ")) }
        #expect(throws: StoreError.duplicateCategoryName) { try store.addCategory(CategoryDraft(name: "thai land")) }
        #expect(throws: StoreError.duplicateCategoryName) { try store.addCategory(CategoryDraft(name: "THAILAND")) }
        #expect(throws: StoreError.invalidColorName("chartreuse")) {
            try store.addCategory(CategoryDraft(name: "Bulgaria", colorName: "chartreuse"))
        }
        #expect(store.categories.count == 1)
    }

    @Test func updateCategoryRenamesAndKeepsItems() throws {
        let store = try makeStore()
        let id = try store.addCategory(CategoryDraft(name: "Thailand"))
        let other = try store.addCategory(CategoryDraft(name: "Work"))
        let item = try store.addItem(ItemDraft(title: "Flights", categoryID: id))
        try store.updateCategory(id) {
            $0.name = "Thailand 2027"
            $0.emoji = "🏝️"
            $0.colorName = "teal"
        }
        let updated = try #require(store.categories.first { $0.id == id })
        #expect(updated.name == "Thailand 2027")
        #expect(updated.emoji == "🏝️")
        #expect(updated.colorName == "teal")
        #expect(store.items(.category(id)).map(\.id) == [item])
        #expect(throws: StoreError.duplicateCategoryName) { try store.updateCategory(other) { $0.name = "thailand2027" } }
        try store.updateCategory(id) { $0.name = "THAILAND 2027" } // renaming itself is fine
    }

    @Test func moveCategoryReorders() throws {
        let store = try makeStore()
        let a = try store.addCategory(CategoryDraft(name: "A"))
        let b = try store.addCategory(CategoryDraft(name: "B"))
        let c = try store.addCategory(CategoryDraft(name: "C"))
        try store.moveCategory(c, toIndex: 0)
        #expect(store.categories.map(\.id) == [c, a, b])
        try store.moveCategory(c, toIndex: 99)
        #expect(store.categories.map(\.id) == [a, b, c])
        #expect(store.categories.map(\.sortIndex) == [0, 1, 2])
        try store.deleteCategory(a)
        #expect(throws: StoreError.categoryNotFound(a)) { try store.moveCategory(a, toIndex: 0) }
    }

    @Test func deleteCategoryMovesItemsToInbox() throws {
        let store = try makeStore()
        let thailand = try store.addCategory(CategoryDraft(name: "Thailand"))
        let item = try store.addItem(ItemDraft(title: "Flights", categoryID: thailand))
        try store.deleteCategory(thailand)
        #expect(store.categories.isEmpty)
        #expect(store.items(.inbox).map(\.id) == [item])
    }

    @Test func openCountCountsTasksNotDoneAndMemos() throws {
        let store = try makeStore()
        let id = try store.addCategory(CategoryDraft(name: "Bulgaria"))
        let done = try store.addItem(ItemDraft(title: "done", categoryID: id))
        try store.addItem(ItemDraft(title: "open", categoryID: id))
        try store.addItem(ItemDraft(title: "memo", kind: .memo, categoryID: id))
        try store.addItem(ItemDraft(title: "inbox"))
        try store.setDone(done, true)
        #expect(store.categories.first?.openCount == 2)
    }

    /// Two devices can each create "Work" before they sync. Editing one of
    /// the twins must still work as long as the edit doesn't touch the name.
    @Test func editingASyncedTwinOnlyChecksWhatChanged() throws {
        let container = try StoreFactory.inMemory()
        let context = ModelContext(container)
        let first = Category(name: "Work", sortIndex: 0)
        let twin = Category(name: "Work", sortIndex: 1)
        context.insert(first)
        context.insert(twin)
        try context.save()
        let store = SwiftDataItemStore(container: container, calendar: TestCalendar.jerusalem)

        try store.updateCategory(twin.id) {
            $0.colorName = "teal"
            $0.emoji = "💼"
        }
        #expect(store.categories.first { $0.id == twin.id }?.colorName == "teal")

        try store.updateCategory(twin.id) { $0.name = "WORK" } // same name, new case
        #expect(store.categories.first { $0.id == twin.id }?.name == "WORK")

        try store.updateCategory(twin.id) { $0.name = "Side projects" }
        let other = try store.addCategory(CategoryDraft(name: "Home"))
        #expect(throws: StoreError.duplicateCategoryName) { try store.updateCategory(other) { $0.name = "side projects" } }
    }
}
