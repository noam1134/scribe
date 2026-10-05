import Foundation

/// Which row shows its inline editor (one at a time), and whether that
/// editor still has to put the caret in its title. The request is taken
/// once per opening: an editor that is rebuilt — its list reloaded, its row
/// re-rendered — must not grab focus again and select the title, where the
/// next keystroke would replace it.
public struct InlineEditing: Equatable, Sendable {
    public private(set) var itemID: UUID?
    private var pendingTitleFocus: UUID?

    public init() {}

    public mutating func open(_ id: UUID) {
        itemID = id
        pendingTitleFocus = id
    }

    public mutating func close() {
        itemID = nil
        pendingTitleFocus = nil
    }

    /// Closes the editor if it is `id`'s.
    public mutating func close(_ id: UUID) {
        if itemID == id { close() }
    }

    /// Selecting another row (or none) closes the editor.
    public mutating func selectionChanged(to id: UUID?) {
        if let itemID, itemID != id { close() }
    }

    /// The editor for `id` appeared: true the first time after `open(id)`.
    public mutating func takeTitleFocus(for id: UUID) -> Bool {
        guard pendingTitleFocus == id, itemID == id else { return false }
        pendingTitleFocus = nil
        return true
    }
}
