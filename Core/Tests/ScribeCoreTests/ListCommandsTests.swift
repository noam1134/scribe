import Foundation
import Testing
@testable import ScribeCore

struct ListCommandsTests {
    let work = CategorySnapshot(name: "Work", sortIndex: 0)
    let task = ItemSnapshot(title: "Call Dan")
    let doneTask = ItemSnapshot(title: "Pay rent", isDone: true)
    let memo = ItemSnapshot(title: "Gate code", kind: .memo)

    func context(focused: Bool = true, editing: Bool = false, selected: ItemSnapshot? = nil) -> ListCommandContext {
        ListCommandContext(listIsFocused: focused, isEditingText: editing, selectedItem: selected, categories: [work])
    }

    @Test func spaceTogglesTheSelectedTask() {
        #expect(ListCommands.action(for: .toggleDone, in: context(selected: task)) == .setDone(task.id, true))
        #expect(ListCommands.action(for: .toggleDone, in: context(selected: doneTask)) == .setDone(doneTask.id, false))
    }

    @Test func spaceDoesNothingForMemosOrWithoutASelection() {
        #expect(ListCommands.action(for: .toggleDone, in: context(selected: memo)) == nil)
        #expect(ListCommands.action(for: .toggleDone, in: context()) == nil)
    }

    @Test func deleteAndEditNeedASelection() {
        #expect(ListCommands.action(for: .delete, in: context(selected: memo)) == .delete(memo))
        #expect(ListCommands.action(for: .edit, in: context(selected: task)) == .edit(task.id))
        #expect(ListCommands.action(for: .delete, in: context()) == nil)
        #expect(ListCommands.action(for: .edit, in: context()) == nil)
    }

    /// Spec §9.3: list focused, not while editing text.
    nonisolated static let listOnly: [ListCommand] = [.toggleDone, .delete, .edit]

    @Test(arguments: listOnly)
    func listCommandsWaitForTheList(command: ListCommand) {
        #expect(ListCommands.action(for: command, in: context(focused: false, selected: task)) == nil)
        #expect(ListCommands.action(for: command, in: context(editing: true, selected: task)) == nil)
    }

    @Test func windowCommandsWorkWhileTyping() {
        let typing = context(focused: false, editing: true, selected: task)
        #expect(ListCommands.action(for: .newItem, in: typing) == .startQuickAdd)
        #expect(ListCommands.action(for: .find, in: typing) == .focusSearch)
        #expect(ListCommands.action(for: .jump(1), in: typing) == .show(.category(work.id)))
        #expect(ListCommands.action(for: .jump(0), in: typing) == .show(.upcoming))
        #expect(ListCommands.action(for: .jump(2), in: typing) == nil)
    }

    @Test func selectionMovesToTheNextRowThenThePrevious() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(ListSelection.afterRemoving(a, from: [a, b, c]) == b)
        #expect(ListSelection.afterRemoving(b, from: [a, b, c]) == c)
        #expect(ListSelection.afterRemoving(c, from: [a, b, c]) == b)
        #expect(ListSelection.afterRemoving(a, from: [a]) == nil)
        #expect(ListSelection.afterRemoving(UUID(), from: [a, b]) == nil)
    }
}
