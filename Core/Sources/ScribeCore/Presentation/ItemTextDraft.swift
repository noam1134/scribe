import Foundation

/// The inline editor's title and notes, each compared with its baseline:
/// what it was when the editor opened or was last saved. Only a field the
/// user changed is written, so an edit that arrived from another device
/// while the editor was open isn't overwritten with stale text.
public struct ItemTextDraft: Equatable, Sendable {
    /// The fields to write; nil leaves the stored value alone.
    public struct Changes: Equatable, Sendable {
        public var title: String?
        public var notes: String?

        public var isEmpty: Bool { title == nil && notes == nil }

        public func apply(to edit: inout ItemEdit) {
            if let title { edit.title = title }
            if let notes { edit.body = notes }
        }
    }

    public var title: String
    public var notes: String
    public private(set) var savedTitle: String
    public private(set) var savedNotes: String

    public init(title: String, notes: String) {
        self.title = title
        self.notes = notes
        savedTitle = title
        savedNotes = notes
    }

    /// The title, trimmed, when it isn't empty (spec §13) and differs from
    /// its baseline; the notes when they differ from theirs.
    public var changes: Changes {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Changes(
            title: trimmed.isEmpty || trimmed == savedTitle ? nil : trimmed,
            notes: notes == savedNotes ? nil : notes
        )
    }

    /// `changes` were written: they become the baseline.
    public mutating func didSave(_ changes: Changes) {
        if let title = changes.title { savedTitle = title }
        if let notes = changes.notes { savedNotes = notes }
    }

    /// An empty title is never saved; put the baseline back in the field.
    public mutating func restoreEmptyTitle() {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = savedTitle }
    }
}
