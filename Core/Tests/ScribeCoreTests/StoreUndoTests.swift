import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct StoreUndoTests {
    final class Errors {
        var all: [any Error] = []
    }

    func make() throws -> (SwiftDataItemStore, UndoManager, StoreUndo, Errors) {
        let store = try makeStore()
        let manager = UndoManager()
        manager.groupsByEvent = false
        let errors = Errors()
        let undo = StoreUndo(store: store, manager: manager) { errors.all.append($0) }
        return (store, manager, undo, errors)
    }

    /// One user action, as AppKit groups it per event.
    func step(_ manager: UndoManager, _ action: () throws -> Void) rethrows {
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        try action()
    }

    @Test func deletingAnItemUndoesAndRedoes() throws {
        let (store, manager, undo, _) = try make()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let id = try store.addItem(ItemDraft(title: "Call Dan", categoryID: work))
        let item = try #require(store.item(id))

        try step(manager) { try undo.deleteItem(item) }
        #expect(store.item(id) == nil)
        #expect(manager.undoActionName == "Delete “Call Dan”")

        manager.undo()
        #expect(store.item(id) == item)
        #expect(manager.redoActionName == "Delete “Call Dan”")

        manager.redo()
        #expect(store.item(id) == nil)
        manager.undo()
        #expect(store.item(id)?.categoryID == work)
    }

    @Test func doneUndoes() throws {
        let (store, manager, undo, _) = try make()
        let id = try store.addItem(ItemDraft(title: "Pay rent"))
        try step(manager) { try undo.setDone(try #require(store.item(id)), true) }
        #expect(store.item(id)?.isDone == true)
        #expect(manager.undoActionName == "Mark as Done")
        manager.undo()
        #expect(store.item(id)?.isDone == false)
        manager.redo()
        #expect(store.item(id)?.isDone == true)
    }

    @Test func deletingACategoryUndoesWithItsItems() throws {
        let (store, manager, undo, _) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭"))
        let item = try store.addItem(ItemDraft(title: "Book flights", categoryID: trip))

        try step(manager) { try undo.deleteCategory(trip) }
        #expect(store.categories.isEmpty)
        #expect(store.item(item)?.categoryID == nil)
        #expect(manager.undoActionName == "Delete “Thailand”")

        manager.undo()
        #expect(store.categories.map(\.id) == [trip])
        #expect(store.item(item)?.categoryID == trip)

        manager.redo()
        #expect(store.categories.isEmpty)
    }

    @Test func editsUndoToWhatTheItemWas() throws {
        let (store, manager, undo, _) = try make()
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let id = try store.addItem(ItemDraft(title: "Fix sink", categoryID: home))

        try step(manager) { try undo.update(id, actionName: "Move to Work") { $0.categoryID = work } }
        #expect(store.item(id)?.categoryID == work)
        #expect(manager.undoActionName == "Move to Work")
        manager.undo()
        #expect(store.item(id)?.categoryID == home)
        manager.redo()
        #expect(store.item(id)?.categoryID == work)
    }

    @Test func undoingAMoveKeepsALaterTitleEdit() throws {
        let (store, manager, undo, _) = try make()
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let id = try store.addItem(ItemDraft(title: "Fix sink", categoryID: home))

        try step(manager) { try undo.update(id, actionName: "Move to Work") { $0.categoryID = work } }
        // Renamed afterwards — in the editor, or on another device.
        try store.updateItem(id) { $0.title = "Fix the kitchen sink" }

        manager.undo()
        #expect(store.item(id)?.categoryID == home)
        #expect(store.item(id)?.title == "Fix the kitchen sink")
        manager.redo()
        #expect(store.item(id)?.categoryID == work)
        #expect(store.item(id)?.title == "Fix the kitchen sink")
    }

    @Test func undoingMakeMemoOnADoneTaskRestoresDone() throws {
        let (store, manager, undo, _) = try make()
        let id = try store.addItem(ItemDraft(title: "Pay rent"))
        try store.setDone(id, true)

        try step(manager) { try undo.update(id, actionName: "Make Memo") { $0.kind = .memo } }
        #expect(store.item(id)?.kind == .memo)
        #expect(store.item(id)?.isDone == false)

        manager.undo()
        #expect(store.item(id)?.kind == .task)
        #expect(store.item(id)?.isDone == true)
        manager.redo()
        #expect(store.item(id)?.kind == .memo)
        #expect(store.item(id)?.isDone == false)
    }

    @Test func anEditThatChangesNothingRegistersNothing() throws {
        let (store, manager, undo, _) = try make()
        let id = try store.addItem(ItemDraft(title: "Fix sink"))
        // No group is open: registering anything would raise.
        try undo.update(id, actionName: "Make Task") { $0.kind = .task }
        #expect(!manager.canUndo)
    }

    @Test func anUndoThatCanNoLongerApplyIsReported() throws {
        let (store, manager, undo, errors) = try make()
        let id = try store.addItem(ItemDraft(title: "Fix sink"))
        try step(manager) { try undo.update(id, actionName: "Make Memo") { $0.kind = .memo } }
        try store.deleteItem(id) // e.g. deleted on another device
        manager.undo()
        #expect(errors.all.count == 1)
        #expect(errors.all.first as? StoreError == .itemNotFound(id))
    }

    @Test func aFailedWriteRegistersNothing() throws {
        let (store, manager, undo, _) = try make()
        let missing = ItemSnapshot(title: "Gone")
        // No group is open: registering anything would raise.
        #expect(throws: StoreError.itemNotFound(missing.id)) { try undo.deleteItem(missing) }
        #expect(!manager.canUndo)
        #expect(store.items(.inbox).isEmpty)
    }

    @Test func withoutAManagerItOnlyWrites() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Water plants"))
        try StoreUndo(store: store, manager: nil).deleteItem(try #require(store.item(id)))
        #expect(store.item(id) == nil)
    }
}
