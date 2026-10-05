import Foundation
import Testing
@testable import ScribeCore

/// A widget or shortcut saved a category id; the category may since have
/// been deleted (on this device or another).
struct CategoryLookupTests {
    let work = CategorySnapshot(name: "Work", sortIndex: 0)
    let trip = CategorySnapshot(name: "Thailand", sortIndex: 1)

    @Test func keepsTheOrderAndMarksDeletedIDs() {
        let deleted = UUID()
        let found = CategoryLookup.categories(withIDs: [trip.id, deleted, work.id], in: [work, trip])
        #expect(found.map(\.id) == [trip.id, deleted, work.id])
        #expect(found.map(\.category) == [trip, nil, work])
    }

    @Test func nothingAskedNothingFound() {
        #expect(CategoryLookup.categories(withIDs: [], in: [work]).isEmpty)
    }
}
