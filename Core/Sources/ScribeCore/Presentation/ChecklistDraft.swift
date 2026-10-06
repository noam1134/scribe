import Foundation

/// The inline editor's checklist, compared with its baseline: the steps as
/// they were when the editor opened or last saved. Blank steps exist only
/// while being typed — they are never written, and a step left blank goes
/// away. The list is written as a whole, and only when it changed.
public struct ChecklistDraft: Equatable, Sendable {
    /// What the editor shows, blank steps included.
    public var steps: [ChecklistItem]
    public private(set) var saved: [ChecklistItem]

    public init(_ steps: [ChecklistItem]) {
        self.steps = steps
        saved = steps
    }

    /// The steps to write — trimmed, blank ones dropped — or nil when that
    /// is what is saved.
    public var changes: [ChecklistItem]? {
        let cleaned = Self.cleaned(steps)
        return cleaned == saved ? nil : cleaned
    }

    /// `changes` were written: they become the baseline.
    public mutating func didSave(_ steps: [ChecklistItem]) {
        saved = steps
    }

    /// The stored list changed under the editor (undo, another device).
    /// Taken only while nothing here is pending, so typing is never lost.
    public mutating func rebase(onto stored: [ChecklistItem]) {
        guard stored != saved, steps == saved else { return }
        steps = stored
        saved = stored
    }

    /// A new blank step after `id` (at the end for nil or an unknown id);
    /// returns its id. A blank last step is reused instead of adding another.
    @discardableResult
    public mutating func add(after id: UUID? = nil) -> UUID {
        if id == nil, let last = steps.last, Self.isBlank(last) { return last.id }
        let step = ChecklistItem(title: "")
        if let id, let index = steps.firstIndex(where: { $0.id == id }) {
            steps.insert(step, at: index + 1)
        } else {
            steps.append(step)
        }
        return step.id
    }

    /// Removes the step; returns the one before it (where the caret goes).
    @discardableResult
    public mutating func remove(_ id: UUID) -> UUID? {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return nil }
        steps.remove(at: index)
        return index > 0 ? steps[index - 1].id : nil
    }

    /// Removes the step if it is blank; true if it did.
    @discardableResult
    public mutating func removeIfBlank(_ id: UUID) -> Bool {
        guard let step = steps.first(where: { $0.id == id }), Self.isBlank(step) else { return false }
        remove(id)
        return true
    }

    public mutating func toggle(_ id: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].isDone.toggle()
    }

    public func isBlank(_ id: UUID) -> Bool {
        steps.first { $0.id == id }.map(Self.isBlank) ?? false
    }

    private static func isBlank(_ step: ChecklistItem) -> Bool {
        step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func cleaned(_ steps: [ChecklistItem]) -> [ChecklistItem] {
        steps.compactMap { step in
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return ChecklistItem(id: step.id, title: title, isDone: step.isDone)
        }
    }
}

/// "2/5" for a row's secondary line; nil without steps.
public struct ChecklistProgress: Equatable, Sendable {
    public let done: Int
    public let total: Int

    public init?(_ steps: [ChecklistItem]) {
        guard !steps.isEmpty else { return nil }
        done = steps.filter(\.isDone).count
        total = steps.count
    }

    public var text: String { "\(done)/\(total)" }

    /// For VoiceOver, which would read "2/5" as a fraction.
    public var spokenText: String { "\(done) of \(total) \(total == 1 ? "step" : "steps") done" }

    public var isComplete: Bool { done == total }
}
