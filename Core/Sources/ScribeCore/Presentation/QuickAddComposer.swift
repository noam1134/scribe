import Foundation
import Observation

/// State behind every in-app quick-add field (spec §8): the text, the live
/// parse, dismissible chips, the task/memo toggle, the category pick and
/// saving. Every item gets a real category — the composer never files to the
/// Inbox (spec §19).
@MainActor
@Observable
public final class QuickAddComposer {
    /// One recognized token shown as a chip. `id` is its position, so two
    /// time chips ("tonight" + "at 9") never collide.
    public struct Chip: Identifiable, Equatable, Sendable {
        public let id: Int
        public let kind: TokenKind
        public let label: String
    }

    public var text: String = ""
    /// The ✓/📝 toggle. `!memo` typed in the text also makes a memo.
    public var isMemo: Bool = false
    /// Category preselected by context (composing from a category screen or
    /// a category link). Ignored once it no longer exists.
    public var defaultCategoryID: UUID?
    /// The category chip the user tapped. Beats a typed `#tag` and the default.
    public private(set) var selectedCategoryID: UUID?
    public private(set) var disabled: Set<TokenKind> = []

    @ObservationIgnored private let store: any ItemStore
    @ObservationIgnored private let parser: QuickAddParser
    @ObservationIgnored private let labels: DueLabels
    @ObservationIgnored private let now: () -> Date

    public init(
        store: any ItemStore,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.parser = QuickAddParser(calendar: calendar)
        self.labels = DueLabels(calendar: calendar, locale: locale)
        self.now = now
    }

    /// Everything a composer UI shows, from one parse and one category
    /// read. Read it once per render (the separate properties each parse).
    public struct LiveParse: Equatable, Sendable {
        public let draft: ParsedDraft
        /// Date, time and kind chips. The category has its own row.
        public let chips: [Chip]
        /// Every category, for the sheet's category row.
        public let categories: [CategorySnapshot]
        /// Where the item would go: the tapped chip, else a matched `#tag`,
        /// else the context default — nil until one of them names a
        /// category that exists.
        public let categoryID: UUID?

        public var canSave: Bool { draft.isValid && categoryID != nil }

        /// Name of a typed `#tag` that matches no category, for a
        /// "+ New category" chip.
        public var unknownCategoryName: String? {
            if case .unknown(let name) = draft.category { return name }
            return nil
        }
    }

    public var liveParse: LiveParse {
        let categories = store.categories
        let date = now()
        let draft = parser.parse(text, categories: categories, now: date, disabled: disabled)
        let today = LocalDay(date, calendar: parser.calendar)
        return LiveParse(
            draft: draft,
            chips: chips(for: draft, today: today),
            categories: categories,
            categoryID: categoryID(for: draft, in: categories)
        )
    }

    public var parsed: ParsedDraft { liveParse.draft }

    public var canSave: Bool { liveParse.canSave }

    public var unknownCategoryName: String? { liveParse.unknownCategoryName }

    public var chips: [Chip] { liveParse.chips }

    /// The user tapped a chip: stop interpreting that kind of token; its
    /// text goes back into the title.
    public func dismiss(_ chip: Chip) {
        disabled.insert(chip.kind)
    }

    /// The user tapped a category chip.
    public func select(_ categoryID: UUID) {
        selectedCategoryID = categoryID
    }

    /// Turns a typed unknown `#tag` into a category and picks it.
    public func createUnknownCategory() throws {
        guard let name = unknownCategoryName else { return }
        let color = CategoryPalette.suggestedColorName(avoiding: store.categories.map(\.colorName))
        selectedCategoryID = try store.addCategory(CategoryDraft(name: name, colorName: color))
    }

    /// Adds the item and clears the composer. Returns nil — and keeps the
    /// text — when there is no title or no category yet. An unknown `#tag`
    /// that wasn't turned into a category stays in the title.
    @discardableResult
    public func save() throws -> UUID? {
        let categories = store.categories
        let date = now()
        var draft = parser.parse(text, categories: categories, now: date, disabled: disabled)
        guard let categoryID = categoryID(for: draft, in: categories) else { return nil }
        if case .unknown = draft.category {
            draft = parser.parse(text, categories: categories, now: date, disabled: disabled.union([.category]))
        }
        guard var item = draft.itemDraft else { return nil }
        if isMemo { item.kind = .memo }
        item.categoryID = categoryID
        let id = try store.addItem(item)
        reset()
        return id
    }

    public func reset() {
        text = ""
        isMemo = false
        disabled = []
        selectedCategoryID = nil
    }

    private func categoryID(for draft: ParsedDraft, in categories: [CategorySnapshot]) -> UUID? {
        func exists(_ id: UUID?) -> UUID? {
            id.flatMap { id in categories.contains { $0.id == id } ? id : nil }
        }
        if let picked = exists(selectedCategoryID) { return picked }
        if case .matched(let tagged) = draft.category, let tagged = exists(tagged) { return tagged }
        return exists(defaultCategoryID)
    }

    private func chips(for draft: ParsedDraft, today: LocalDay) -> [Chip] {
        var shownTime = false
        return draft.tokens.enumerated().compactMap { index, token in
            // "tonight at 9" is two time tokens but one time: show one chip.
            if token.kind == .time {
                if shownTime { return nil }
                shownTime = true
            }
            guard let label = label(for: token, in: draft, today: today) else { return nil }
            return Chip(id: index, kind: token.kind, label: label)
        }
    }

    private func label(for token: RecognizedToken, in draft: ParsedDraft, today: LocalDay) -> String? {
        switch token.kind {
        case .category:
            return nil // shown by the category row
        case .kind:
            return "Memo"
        case .date:
            return draft.due.map { labels.dayTitle($0.day, today: today) }
        case .time:
            return draft.due?.minute.map { labels.time($0) }
        }
    }
}
