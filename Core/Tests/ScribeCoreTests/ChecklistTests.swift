import Foundation
import Testing
@testable import ScribeCore

struct ChecklistCodingTests {
    let boots = ChecklistItem(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, title: "Boots", isDone: true)
    let gloves = ChecklistItem(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, title: "כפפות")

    @Test func stepsRoundTrip() {
        let json = ChecklistCoding.encode([boots, gloves])
        #expect(ChecklistCoding.decode(json) == [boots, gloves])
    }

    @Test func encodingIsCompactAndStable() {
        #expect(ChecklistCoding.encode([boots]) == #"[{"id":"00000000-0000-4000-8000-000000000001","isDone":true,"title":"Boots"}]"#)
    }

    @Test func noStepsIsTheEmptyDefault() {
        #expect(ChecklistCoding.encode([]) == "")
        #expect(ChecklistCoding.decode("") == [])
    }

    @Test(arguments: ["{", "null", "42", #"{"id":"x"}"#, "[1, 2]", "not json at all"])
    func unreadableJSONIsNoSteps(_ json: String) {
        #expect(ChecklistCoding.decode(json) == [])
    }

    @Test func anUnreadableStepIsSkipped() {
        let json = #"[{"id":"00000000-0000-4000-8000-000000000001","title":"Boots","isDone":true}, {"title":"no id"}, 7]"#
        #expect(ChecklistCoding.decode(json) == [boots])
    }

    @Test func aStepMissingFieldsStillReads() {
        let json = #"[{"id":"00000000-0000-4000-8000-000000000002","future":"field"}]"#
        #expect(ChecklistCoding.decode(json) == [ChecklistItem(id: gloves.id, title: "", isDone: false)])
    }

    @Test func theModelKeepsStepsAsJSON() {
        let item = Item(title: "Pack for Borovets")
        #expect(item.checklistJSON == "")
        #expect(item.snapshot.checklist == [])
        item.checklist = [boots, gloves]
        #expect(item.checklistJSON == ChecklistCoding.encode([boots, gloves]))
        #expect(item.snapshot.checklist == [boots, gloves])
        item.checklist = []
        #expect(item.checklistJSON == "")
    }

    @Test func corruptStoredJSONReadsAsNoSteps() {
        let item = Item(title: "x")
        item.checklistJSON = "[{\"id\": broken"
        #expect(item.checklist == [])
        #expect(item.snapshot.checklist == [])
    }
}

@MainActor
struct ChecklistStoreTests {
    let steps = [ChecklistItem(title: "Boots", isDone: true), ChecklistItem(title: "Gloves"), ChecklistItem(title: "Passport")]

    @Test func anEditWritesTheChecklist() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let id = try store.addItem(ItemDraft(title: "Pack for Borovets"))
        #expect(store.item(id)?.checklist == [])
        clock.advance(minutes: 1)
        try store.updateItem(id) { $0.checklist = steps }
        let item = try #require(store.item(id))
        #expect(item.checklist == steps)
        #expect(item.updatedAt == clock.now)
    }

    @Test func theEditStartsFromTheStoredChecklist() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Pack"))
        try store.updateItem(id) { $0.checklist = steps }
        var seen: [ChecklistItem] = []
        try store.updateItem(id) {
            seen = $0.checklist
            $0.checklist[1].isDone = true
        }
        #expect(seen == steps)
        #expect(store.item(id)?.checklist.map(\.isDone) == [true, true, false])
    }

    @Test func otherEditsKeepTheChecklist() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Pack"))
        try store.updateItem(id) { $0.checklist = steps }
        try store.updateItem(id) {
            $0.title = "Pack for Borovets"
            $0.kind = .memo
        }
        #expect(store.item(id)?.checklist == steps)
        try store.setDone(id, true)
        #expect(store.item(id)?.checklist == steps)
    }

    @Test func clearingTheChecklist() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Pack"))
        try store.updateItem(id) { $0.checklist = steps }
        try store.updateItem(id) { $0.checklist = [] }
        #expect(store.item(id)?.checklist == [])
    }

    @Test func restoringADeletedItemBringsItsChecklistBack() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Pack"))
        try store.updateItem(id) { $0.checklist = steps }
        let snapshot = try #require(store.item(id))
        try store.deleteItem(id)
        try store.restoreItem(snapshot)
        #expect(store.item(id) == snapshot)
    }

    @Test func searchAndAgendaSnapshotsCarryTheChecklist() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Pack", due: DueDate(day: LocalDay(2026, 10, 5))))
        try store.updateItem(id) { $0.checklist = steps }
        #expect(store.items(.search("Pack")).first?.checklist == steps)
        #expect(store.datedOpenItems().first?.checklist == steps)
    }

    @Test func exportIncludesTheChecklist() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let id = try store.addItem(ItemDraft(title: "Pack"))
        try store.updateItem(id) { $0.checklist = steps }
        clock.advance(minutes: 1) // the export is in creation order
        try store.addItem(ItemDraft(title: "No steps"))
        let data = try store.exportJSON()
        let document = try ExportDocument.decoder().decode(ExportDocument.self, from: data)
        #expect(document.items.map(\.checklist) == [steps, []])
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"title\" : \"Gloves\""))
    }

    @Test func anExportWithoutChecklistsStillReads() throws {
        let json = """
        {"version": 1, "exportedAt": "2026-10-05T07:00:00.000Z", "categories": [], "items": [{
          "id": "00000000-0000-4000-8000-000000000001", "title": "Old", "body": "", "kind": "task",
          "isDone": false, "createdAt": "2026-10-05T07:00:00.000Z", "updatedAt": "2026-10-05T07:00:00.000Z"
        }]}
        """
        let document = try ExportDocument.decoder().decode(ExportDocument.self, from: Data(json.utf8))
        #expect(document.items.first?.checklist == nil)
    }

    @Test func undoAndRedoAStepChange() throws {
        let store = try makeStore()
        let manager = UndoManager()
        manager.groupsByEvent = false
        let undo = StoreUndo(store: store, manager: manager)
        let id = try store.addItem(ItemDraft(title: "Pack"))
        try store.updateItem(id) { $0.checklist = steps }
        var checked = steps
        checked[1].isDone = true

        manager.beginUndoGrouping()
        try undo.update(id, actionName: "Check Step") { $0.checklist = checked }
        manager.endUndoGrouping()
        #expect(manager.undoActionName == "Check Step")

        manager.undo()
        #expect(store.item(id)?.checklist == steps)
        manager.redo()
        #expect(store.item(id)?.checklist == checked)
    }
}

struct ChecklistDraftTests {
    let boots = ChecklistItem(title: "Boots")
    let gloves = ChecklistItem(title: "Gloves")

    @Test func nothingChangedWritesNothing() {
        let draft = ChecklistDraft([boots, gloves])
        #expect(draft.changes == nil)
    }

    @Test func aToggleIsAChange() {
        var draft = ChecklistDraft([boots, gloves])
        draft.toggle(gloves.id)
        #expect(draft.changes == [boots, ChecklistItem(id: gloves.id, title: "Gloves", isDone: true)])
        draft.toggle(gloves.id)
        #expect(draft.changes == nil)
    }

    @Test func titlesAreTrimmedAndBlankStepsNeverWritten() {
        var draft = ChecklistDraft([boots])
        let new = draft.add()
        #expect(draft.changes == nil, "a blank step alone is no change")
        draft.steps[1].title = "  Passport \n"
        #expect(draft.changes == [boots, ChecklistItem(id: new, title: "Passport")])
        draft.steps[0].title = "   "
        #expect(draft.changes == [ChecklistItem(id: new, title: "Passport")])
    }

    @Test func savingMovesTheBaseline() throws {
        var draft = ChecklistDraft([])
        let id = draft.add()
        draft.steps[0].title = "Boots"
        let changes = try #require(draft.changes)
        draft.didSave(changes)
        #expect(draft.changes == nil)
        #expect(draft.saved == [ChecklistItem(id: id, title: "Boots")])
    }

    @Test func addingAfterAStepInsertsBelowIt() {
        var draft = ChecklistDraft([boots, gloves])
        let new = draft.add(after: boots.id)
        #expect(draft.steps.map(\.id) == [boots.id, new, gloves.id])
        #expect(draft.steps[1].title == "")
        let last = draft.add(after: UUID())
        #expect(draft.steps.last?.id == last, "an unknown step adds at the end")
    }

    @Test func addingAtTheEndReusesABlankLastStep() {
        var draft = ChecklistDraft([boots])
        let first = draft.add()
        let again = draft.add()
        #expect(again == first)
        #expect(draft.steps.count == 2)
    }

    @Test func removingReturnsTheStepBefore() {
        var draft = ChecklistDraft([boots, gloves])
        let beforeGloves = draft.remove(gloves.id)
        #expect(beforeGloves == boots.id)
        #expect(draft.steps == [boots])
        let beforeBoots = draft.remove(boots.id)
        #expect(beforeBoots == nil)
        #expect(draft.steps.isEmpty)
        #expect(draft.changes == [])
        let unknown = draft.remove(UUID())
        #expect(unknown == nil)
    }

    @Test func onlyABlankStepIsRemovedAsBlank() {
        var draft = ChecklistDraft([boots])
        let blank = draft.add()
        draft.steps[1].title = "  "
        #expect(draft.isBlank(blank))
        #expect(!draft.isBlank(boots.id))
        let removedBoots = draft.removeIfBlank(boots.id)
        #expect(!removedBoots)
        let removedBlank = draft.removeIfBlank(blank)
        #expect(removedBlank)
        #expect(draft.steps == [boots])
    }

    @Test func anIdleDraftFollowsTheStore() {
        var draft = ChecklistDraft([boots])
        draft.rebase(onto: [boots, gloves])
        #expect(draft.steps == [boots, gloves])
        #expect(draft.changes == nil)
    }

    @Test func aDraftWithPendingWorkIgnoresTheStore() {
        var draft = ChecklistDraft([boots])
        draft.add()
        draft.rebase(onto: [gloves])
        #expect(draft.steps.count == 2, "a step being typed stays")
        #expect(draft.saved == [boots])
    }
}

struct ChecklistProgressTests {
    @Test func noStepsShowNothing() {
        #expect(ChecklistProgress([]) == nil)
    }

    @Test func doneOverTotal() throws {
        let progress = try #require(ChecklistProgress([
            ChecklistItem(title: "a", isDone: true), ChecklistItem(title: "b", isDone: true),
            ChecklistItem(title: "c"), ChecklistItem(title: "d"), ChecklistItem(title: "e"),
        ]))
        #expect(progress.text == "2/5")
        #expect(progress.spokenText == "2 of 5 steps done")
        #expect(!progress.isComplete)
    }

    @Test func oneStep() throws {
        let progress = try #require(ChecklistProgress([ChecklistItem(title: "a", isDone: true)]))
        #expect(progress.text == "1/1")
        #expect(progress.spokenText == "1 of 1 step done")
        #expect(progress.isComplete)
    }
}
