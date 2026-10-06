import ScribeCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The inline editor's checklist, under the notes: each step a small circle
/// and a field in the step's own text direction, then "Add Step". Return in
/// a step adds the next one; Return or Delete in an empty step removes it,
/// and so does leaving a step empty or its × button. Checking a step is
/// handed up to be saved at once; step text is saved with the editor's.
struct ChecklistEditor: View {
    @Binding var draft: ChecklistDraft
    /// The checked circle's color: the item's category.
    let tint: Color
    /// A step was checked (true) or unchecked.
    let toggled: (_ isDone: Bool) -> Void

    @FocusState private var focused: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(draft.steps) { step in
                row(step)
            }
            addButton
        }
        .font(.callout)
        .onChange(of: focused) { old, new in
            // A step left empty goes away.
            guard let old, old != new, draft.isBlank(old) else { return }
            withAnimation(.snappy) { _ = draft.removeIfBlank(old) }
        }
    }

    private func row(_ step: ChecklistItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                draft.toggle(step.id)
                toggled(!step.isDone)
            } label: {
                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(step.isDone ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step.isDone ? "Mark step not done" : "Mark step done")
            .accessibilityIdentifier("stepCheckbox-\(step.title)")
            TextField("Step", text: title(of: step.id))
                .foregroundStyle(step.isDone ? .secondary : .primary)
                .focused($focused, equals: step.id)
                .submitLabel(.next)
                .onSubmit { submit(step.id) }
                .onKeyPress(.delete) { deleteKey(in: step.id) }
                .layoutDirection(of: step.title)
                .accessibilityIdentifier("stepField")
            if focused == step.id {
                Button {
                    remove(step.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keepsKeyboard()
                .accessibilityLabel("Delete Step")
            }
        }
    }

    private var addButton: some View {
        Button {
            let id = withAnimation(.snappy) { draft.add() }
            focused = id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.tertiary)
                Text("Add Step")
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keepsKeyboard()
        .accessibilityIdentifier("addStep")
    }

    /// Bound by id, not by index: a removed step's field may still write once.
    private func title(of id: UUID) -> Binding<String> {
        Binding(
            get: { draft.steps.first { $0.id == id }?.title ?? "" },
            set: { title in
                guard let index = draft.steps.firstIndex(where: { $0.id == id }) else { return }
                draft.steps[index].title = title
            }
        )
    }

    /// Return: the next step, below this one. In an empty step: the list
    /// ends there.
    private func submit(_ id: UUID) {
        if draft.isBlank(id) {
            withAnimation(.snappy) { _ = draft.remove(id) }
            focused = nil
        } else {
            let next = withAnimation(.snappy) { draft.add(after: id) }
            focused = next
        }
    }

    /// Delete in an empty step removes it; the caret goes to the step above.
    private func deleteKey(in id: UUID) -> KeyPress.Result {
        guard draft.steps.first(where: { $0.id == id })?.title.isEmpty == true else { return .ignored }
        remove(id)
        return .handled
    }

    private func remove(_ id: UUID) {
        let previous = withAnimation(.snappy) { draft.remove(id) }
        focused = previous
        #if os(macOS)
        // AppKit selects a field's text when it takes the focus: put the
        // caret at the end instead, so the next Delete doesn't clear it.
        if previous != nil {
            Task { @MainActor in
                (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil)
            }
        }
        #endif
    }
}

private extension View {
    /// iPhone: a tap here leaves the keyboard up, so the caret can move
    /// straight to the step it opens.
    @ViewBuilder func keepsKeyboard() -> some View {
        #if os(iOS)
        keepsKeyboardOnTap()
        #else
        self
        #endif
    }
}
