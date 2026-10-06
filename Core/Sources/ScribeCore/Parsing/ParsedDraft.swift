import Foundation

public enum TokenKind: String, Hashable, Sendable, CaseIterable {
    case category, kind, date, time
    /// A category named in plain words: "… in Thailand", "… לעבודה".
    case mention
}

/// A recognized trailing token, shown as a chip in quick-add UIs.
public struct RecognizedToken: Equatable, Sendable {
    public let kind: TokenKind
    /// The text as typed, e.g. "#thai", "in 3 days", "ב-9".
    public let text: String
}

public enum CategoryMatch: Equatable, Sendable {
    case none
    case matched(UUID)
    /// `#name` that matches no category. UI offers "+ New category".
    case unknown(String)
}

public struct ParsedDraft: Equatable, Sendable {
    public var title: String
    public var kind: ItemKind
    public var category: CategoryMatch
    public var due: DueDate?
    /// Enabled recognized tokens, in input order.
    public var tokens: [RecognizedToken]
    /// The category a trailing mention names ("… for work"). Never set
    /// together with a `#tag` for another category: the tag wins and the
    /// mention stays in the title.
    public var mentionedCategoryID: UUID?

    public var isValid: Bool { !title.isEmpty }

    /// nil when the title is empty. A `#tag` beats a mention; an unknown
    /// category becomes the Inbox.
    public var itemDraft: ItemDraft? {
        guard isValid else { return nil }
        var categoryID = mentionedCategoryID
        if case .matched(let id) = category { categoryID = id }
        return ItemDraft(title: title, kind: kind, categoryID: categoryID, due: due)
    }
}

/// A recognized time of day.
struct TimeValue: Equatable, Sendable {
    /// Minutes after midnight.
    let minute: Int
    /// "tonight" / "הערב" mean today even if 20:00 already passed.
    let pinsToday: Bool
    /// Written with am/pm (or a named time like "noon"). Next to "tonight", a
    /// time without it reads as evening: "tonight at 9" is 21:00.
    var isUnambiguous: Bool = false
}
