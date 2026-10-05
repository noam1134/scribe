import Foundation
import Testing
@testable import ScribeCore

struct SidebarTests {
    let work = CategorySnapshot(name: "Work", sortIndex: 0)
    let trip = CategorySnapshot(name: "Thailand", sortIndex: 1)
    let home = CategorySnapshot(name: "Home", sortIndex: 2)
    var categories: [CategorySnapshot] { [work, trip, home] }

    @Test func entriesKnowTheirListAndCategory() {
        #expect(SidebarEntry.upcoming.filter == nil)
        #expect(SidebarEntry.inbox.filter == .inbox)
        #expect(SidebarEntry.category(work.id).filter == .category(work.id))
        #expect(SidebarEntry.upcoming.categoryID == nil)
        #expect(SidebarEntry.inbox.categoryID == nil)
        #expect(SidebarEntry.category(work.id).categoryID == work.id)
    }

    @Test func inboxShowsWhileItHoldsItemsOrIsSelected() {
        #expect(!Sidebar.showsInbox(itemCount: 0, selection: .upcoming))
        #expect(Sidebar.showsInbox(itemCount: 2, selection: .upcoming))
        #expect(Sidebar.showsInbox(itemCount: 0, selection: .inbox))
    }

    @Test func digitShortcuts() {
        #expect(Sidebar.entry(forShortcutDigit: 0, categories: categories) == .upcoming)
        #expect(Sidebar.entry(forShortcutDigit: 1, categories: categories) == .category(work.id))
        #expect(Sidebar.entry(forShortcutDigit: 3, categories: categories) == .category(home.id))
        #expect(Sidebar.entry(forShortcutDigit: 4, categories: categories) == nil)
        #expect(Sidebar.entry(forShortcutDigit: 10, categories: categories) == nil)
        #expect(Sidebar.entry(forShortcutDigit: -1, categories: categories) == nil)
    }

    @Test func onlyNineCategoriesGetDigits() {
        let many = (0..<12).map { CategorySnapshot(name: "C\($0)", sortIndex: Double($0)) }
        #expect(Sidebar.entry(forShortcutDigit: 9, categories: many) == .category(many[8].id))
        #expect(Sidebar.shortcutDigit(for: many[8].id, categories: many) == 9)
        #expect(Sidebar.shortcutDigit(for: many[9].id, categories: many) == nil)
    }

    @Test func aCategoryDeletedElsewhereFallsBackToUpcoming() {
        let ids = categories.map(\.id)
        #expect(Sidebar.validated(.category(trip.id), categoryIDs: ids) == .category(trip.id))
        #expect(Sidebar.validated(.category(UUID()), categoryIDs: ids) == .upcoming)
        #expect(Sidebar.validated(.inbox, categoryIDs: []) == .inbox)
        #expect(Sidebar.validated(.upcoming, categoryIDs: []) == .upcoming)
    }

    @Test func deletingTheSelectedCategorySelectsItsNeighbour() {
        #expect(Sidebar.selection(afterDeleting: work.id, from: categories) == .category(trip.id))
        #expect(Sidebar.selection(afterDeleting: trip.id, from: categories) == .category(home.id))
        #expect(Sidebar.selection(afterDeleting: home.id, from: categories) == .category(trip.id))
        #expect(Sidebar.selection(afterDeleting: work.id, from: [work]) == .upcoming)
        #expect(Sidebar.selection(afterDeleting: UUID(), from: categories) == .upcoming)
    }
}
