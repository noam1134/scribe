import Foundation
import Observation

/// State behind every in-app quick-add field (spec §8): the text, the live
/// parse, dismissible chips, the task/memo toggle, the category pick and
/// saving. Every item gets a real category — the composer never files to the
/// Inbox (spec §19).
///
/// The category comes from, strongest first: a tapped chip, a `#tag`, a
/// mention in the text ("… for work"), the context default, then the
/// on-device model's suggestion. A mention that doesn't decide the category
/// stays in the title.
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
    /// Multi-line notes, saved as the item’s body without surrounding blank
    /// space. Never parsed.
    public var notes: String = ""
    /// The ✓/📝 toggle. `!memo` typed in the text also makes a memo.
    public var isMemo: Bool = false
    /// Category preselected by context (composing from a category screen or
    /// a category link). Ignored once it no longer exists.
    public var defaultCategoryID: UUID?
    /// The category chip the user tapped. Beats a typed `#tag` and the default.
    public private(set) var selectedCategoryID: UUID?
    public private(set) var disabled: Set<TokenKind> = []
    /// The model's latest answer, and the text it was for. Its category
    /// stays picked while the text changes, until the next answer; its title
    /// only applies to that exact text.
    private var suggestion: (text: String, value: CategorySuggestion)?

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
        /// What picked `categoryID`.
        public let categorySource: CategorySource?
        /// What to ask the on-device model, while nothing but the model
        /// could pick a category: a title, categories to choose from, no
        /// unknown `#tag`.
        public let suggestionRequest: SuggestionRequest?

        public var canSave: Bool { draft.isValid && categoryID != nil }

        /// The pick was worked out from the text (a mention or the model),
        /// not chosen: the row marks it.
        public var categoryIsGuess: Bool { categorySource == .mention || categorySource == .suggestion }

        /// Name of a typed `#tag` that matches no category, for a
        /// "+ New category" chip.
        public var unknownCategoryName: String? {
            if case .unknown(let name) = draft.category { return name }
            return nil
        }
    }

    public enum CategorySource: Equatable, Sendable {
        case tapped, tag, mention, context, suggestion
    }

    /// The model's input. `title` is the parser's title — the model's own
    /// title is checked against it.
    public struct SuggestionRequest: Hashable, Sendable {
        public let text: String
        public let title: String
        public let categoryNames: [String]
    }

    public var liveParse: LiveParse {
        let categories = store.categories
        let date = now()
        let resolved = resolve(categories: categories, now: date)
        let today = LocalDay(date, calendar: parser.calendar)
        return LiveParse(
            draft: resolved.draft,
            chips: chips(for: resolved.draft, today: today),
            categories: categories,
            categoryID: resolved.categoryID,
            categorySource: resolved.source,
            suggestionRequest: resolved.request
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

    /// The model answered `request`: `categoryName` (nil for none) and its
    /// cleaned title. Ignored when the text has changed since; a name that
    /// isn't one of the categories clears the suggestion.
    public func applySuggestion(categoryName: String?, title: String?, for request: SuggestionRequest) {
        guard request.text == text else { return }
        let checked = CategorySuggestion.checked(categoryName: categoryName, suggestedTitle: title, for: request.title, categories: store.categories)
        suggestion = checked.map { (request.text, $0) }
    }

    /// Something stronger than the model decides now, or there is nothing
    /// to file.
    public func clearSuggestion() {
        if suggestion != nil { suggestion = nil }
    }

    /// Turns a typed unknown `#tag` into a category and picks it.
    public func createUnknownCategory() throws {
        guard let name = unknownCategoryName else { return }
        let color = CategoryPalette.suggestedColorName(avoiding: store.categories.map(\.colorName))
        selectedCategoryID = try store.addCategory(CategoryDraft(name: name, colorName: color))
    }

    /// Adds the item and clears the composer. Returns nil — and keeps the
    /// text and notes — when there is no title or no category yet. An unknown `#tag`
    /// that wasn't turned into a category stays in the title.
    @discardableResult
    public func save() throws -> UUID? {
        let categories = store.categories
        let date = now()
        var resolved = resolve(categories: categories, now: date)
        guard let categoryID = resolved.categoryID else { return nil }
        if case .unknown = resolved.draft.category {
            resolved.draft = parser.parse(text, categories: categories, now: date, disabled: resolved.disabled.union([.category]))
        }
        guard var item = resolved.draft.itemDraft else { return nil }
        if isMemo { item.kind = .memo }
        item.categoryID = categoryID
        item.body = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = try store.addItem(item)
        reset()
        return id
    }

    public func reset() {
        text = ""
        notes = ""
        isMemo = false
        disabled = []
        selectedCategoryID = nil
        suggestion = nil
    }

    private struct Resolved {
        var draft: ParsedDraft
        /// The token kinds `draft` was parsed without.
        var disabled: Set<TokenKind>
        var categoryID: UUID?
        var source: CategorySource?
        var request: SuggestionRequest?
    }

    private func resolve(categories: [CategorySnapshot], now date: Date) -> Resolved {
        var off = disabled
        var draft = parser.parse(text, categories: categories, now: date, disabled: off)
        let pick = pick(for: draft, in: categories)
        if let mentioned = draft.mentionedCategoryID, pick?.id != mentioned {
            // A tapped chip overrode the mention: its words are the title's.
            off.insert(.mention)
            draft = parser.parse(text, categories: categories, now: date, disabled: off)
        }
        var request: SuggestionRequest?
        let unknownTag = if case .unknown = draft.category { true } else { false }
        if pick == nil || pick?.source == .suggestion, draft.isValid, !categories.isEmpty, !unknownTag {
            request = SuggestionRequest(text: text, title: draft.title, categoryNames: categories.map(\.name))
        }
        if pick?.source == .suggestion, let suggestion, suggestion.text == text {
            draft.title = suggestion.value.title
        }
        return Resolved(draft: draft, disabled: off, categoryID: pick?.id, source: pick?.source, request: request)
    }

    private func pick(for draft: ParsedDraft, in categories: [CategorySnapshot]) -> (id: UUID, source: CategorySource)? {
        func exists(_ id: UUID?) -> UUID? {
            id.flatMap { id in categories.contains { $0.id == id } ? id : nil }
        }
        if let picked = exists(selectedCategoryID) { return (picked, .tapped) }
        if case .matched(let tagged) = draft.category, let tagged = exists(tagged) { return (tagged, .tag) }
        if let mentioned = exists(draft.mentionedCategoryID) { return (mentioned, .mention) }
        if let context = exists(defaultCategoryID) { return (context, .context) }
        if let suggested = exists(suggestion?.value.categoryID) { return (suggested, .suggestion) }
        return nil
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
        case .category, .mention:
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
