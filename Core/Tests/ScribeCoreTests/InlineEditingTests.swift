import Foundation
import Testing
@testable import ScribeCore

struct InlineEditingTests {
    let a = UUID()
    let b = UUID()

    func take(_ editing: inout InlineEditing, _ id: UUID) -> Bool {
        editing.takeTitleFocus(for: id)
    }

    @Test func openingAsksForTitleFocusOnce() {
        var editing = InlineEditing()
        editing.open(a)
        #expect(editing.itemID == a)
        #expect(take(&editing, a))
        // The editor rebuilt (list identity changed, row re-rendered): it
        // must not grab focus again and select the title under the cursor.
        #expect(!take(&editing, a))
        #expect(editing.itemID == a)
    }

    @Test func onlyTheOpenedRowTakesFocus() {
        var editing = InlineEditing()
        editing.open(a)
        #expect(!take(&editing, b))
        #expect(take(&editing, a))
    }

    @Test func reopeningAsksAgain() {
        var editing = InlineEditing()
        editing.open(a)
        _ = editing.takeTitleFocus(for: a)
        editing.close()
        #expect(editing.itemID == nil)
        #expect(!take(&editing, a))
        editing.open(a)
        #expect(take(&editing, a))
    }

    @Test func closingDropsAnUntakenRequest() {
        var editing = InlineEditing()
        editing.open(a)
        editing.close()
        editing.open(b)
        #expect(!take(&editing, a))
        #expect(take(&editing, b))
    }

    @Test func selectingAnotherRowCloses() {
        var editing = InlineEditing()
        editing.open(a)
        editing.selectionChanged(to: a)
        #expect(editing.itemID == a)
        editing.selectionChanged(to: b)
        #expect(editing.itemID == nil)
        editing.open(a)
        editing.selectionChanged(to: nil)
        #expect(editing.itemID == nil)
    }

    @Test func closingOneRowLeavesAnotherAlone() {
        var editing = InlineEditing()
        editing.open(a)
        editing.close(b)
        #expect(editing.itemID == a)
        editing.close(a)
        #expect(editing.itemID == nil)
    }
}
