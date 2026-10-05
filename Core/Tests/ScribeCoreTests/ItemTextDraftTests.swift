import Foundation
import Testing
@testable import ScribeCore

struct ItemTextDraftTests {
    typealias Changes = ItemTextDraft.Changes

    @Test func nothingChangedWritesNothing() {
        let draft = ItemTextDraft(title: "Pay rent", notes: "by transfer")
        #expect(draft.changes.isEmpty)
    }

    @Test func aChangedTitleIsWrittenTrimmedAndAlone() {
        var draft = ItemTextDraft(title: "Pay rent", notes: "")
        draft.title = "  Pay rent now "
        #expect(draft.changes == Changes(title: "Pay rent now", notes: nil))
    }

    @Test func spacesAroundTheSameTitleAreNoChange() {
        var draft = ItemTextDraft(title: "Pay rent", notes: "")
        draft.title = "Pay rent  "
        #expect(draft.changes.isEmpty)
    }

    @Test func changedNotesAreWrittenAlone() {
        var draft = ItemTextDraft(title: "Pay rent", notes: "")
        draft.notes = "by transfer"
        #expect(draft.changes == Changes(title: nil, notes: "by transfer"))
    }

    @Test func notesAreStillWrittenWhenTheTitleWasCleared() {
        var draft = ItemTextDraft(title: "Pay rent", notes: "")
        draft.title = "   "
        draft.notes = "by transfer"
        #expect(draft.changes == Changes(title: nil, notes: "by transfer"))
    }

    @Test func aClearedTitleAloneWritesNothing() {
        var draft = ItemTextDraft(title: "Pay rent", notes: "")
        draft.title = ""
        #expect(draft.changes.isEmpty)
    }

    /// Return saves, then the editor disappears: the second look finds
    /// nothing left to write. Typing the old title back is a real change.
    @Test func savingMovesTheBaseline() {
        var draft = ItemTextDraft(title: "Pay rent", notes: "")
        draft.title = "Pay rent now"
        draft.didSave(draft.changes)
        #expect(draft.changes.isEmpty)
        draft.title = "Pay rent"
        #expect(draft.changes == Changes(title: "Pay rent", notes: nil))
    }

    @Test func savingMovesOnlyTheWrittenFields() {
        var draft = ItemTextDraft(title: "Pay rent", notes: "")
        draft.title = ""
        draft.notes = "by transfer"
        draft.didSave(draft.changes)
        #expect(draft.changes.isEmpty)
        draft.restoreEmptyTitle()
        #expect(draft.title == "Pay rent")
        #expect(draft.notes == "by transfer")
    }

    @Test func anEmptyTitleIsPutBackFromTheBaseline() {
        var draft = ItemTextDraft(title: "Pay rent", notes: "")
        draft.title = "Pay rent now"
        draft.didSave(draft.changes)
        draft.title = " "
        draft.restoreEmptyTitle()
        #expect(draft.title == "Pay rent now")
        draft.title = "Pay"
        draft.restoreEmptyTitle()
        #expect(draft.title == "Pay")
    }

    @Test func changesApplyOnlyTheirOwnFields() {
        var edit = ItemEdit(title: "From the Mac", body: "Mac notes", kind: .task, categoryID: nil, due: nil)
        Changes(title: nil, notes: "mine").apply(to: &edit)
        #expect(edit.title == "From the Mac")
        #expect(edit.body == "mine")
        Changes(title: "Mine", notes: nil).apply(to: &edit)
        #expect(edit.title == "Mine")
        #expect(edit.body == "mine")
    }

    /// The row stayed open while the Mac renamed the item; saving the notes
    /// typed on the iPhone keeps the Mac's title.
    @MainActor
    @Test func aTitleEditedElsewhereSurvivesSavingTheNotes() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Pay rent"))
        let opened = try #require(store.item(id))
        var draft = ItemTextDraft(title: opened.title, notes: opened.body)
        try store.updateItem(id) { $0.title = "Pay rent (from the Mac)" }
        draft.notes = "by transfer"
        let changes = draft.changes
        try store.updateItem(id) { changes.apply(to: &$0) }
        #expect(store.item(id)?.title == "Pay rent (from the Mac)")
        #expect(store.item(id)?.body == "by transfer")
    }
}
