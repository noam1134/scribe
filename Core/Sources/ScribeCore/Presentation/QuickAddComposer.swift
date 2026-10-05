import Foundation
import Observation

/// State behind every in-app quick-add field (spec §8): the text, the live
/// parse, dismissible chips, the task/memo toggle and saving.
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
    /// Category to use when the text has no `#tag` (e.g. composing from a
    /// category screen or a category widget).
    public var defaultCategoryID: UUID?
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

    public var parsed: ParsedDraft {
        parser.parse(text, categories: store.categories, now: now(), disabled: disabled)
    }

    public var canSave: Bool { parsed.isValid }

    /// Name of a typed `#tag` that matches no category, for a
    /// "+ New category" chip.
    public var unknownCategoryName: String? {
        if case .unknown(let name) = parsed.category { return name }
        return nil
    }

    public var chips: [Chip] {
        let draft = parsed
        let today = LocalDay(now(), calendar: parser.calendar)
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

    /// The user tapped a chip: stop interpreting that kind of token; its
    /// text goes back into the title.
    public func dismiss(_ chip: Chip) {
        disabled.insert(chip.kind)
    }

    public func createUnknownCategory() throws {
        guard let name = unknownCategoryName else { return }
        let color = CategoryPalette.suggestedColorName(avoiding: store.categories.map(\.colorName))
        try store.addCategory(CategoryDraft(name: name, colorName: color))
    }

    /// Adds the item and clears the composer. Returns nil when there is no
    /// title. An unknown `#tag` that wasn't turned into a category stays in
    /// the title instead of being dropped.
    @discardableResult
    public func save() throws -> UUID? {
        var draft = parsed
        if case .unknown = draft.category {
            draft = parser.parse(text, categories: store.categories, now: now(), disabled: disabled.union([.category]))
        }
        guard var item = draft.itemDraft else { return nil }
        if isMemo { item.kind = .memo }
        if item.categoryID == nil, case .none = draft.category { item.categoryID = defaultCategoryID }
        let id = try store.addItem(item)
        reset()
        return id
    }

    public func reset() {
        text = ""
        isMemo = false
        disabled = []
    }

    private func label(for token: RecognizedToken, in draft: ParsedDraft, today: LocalDay) -> String? {
        switch token.kind {
        case .category:
            guard case .matched(let id) = draft.category,
                  let category = store.categories.first(where: { $0.id == id }) else { return nil }
            return category.emoji.isEmpty ? category.name : "\(category.emoji) \(category.name)"
        case .kind:
            return "Memo"
        case .date:
            return draft.due.map { labels.dayTitle($0.day, today: today) }
        case .time:
            return draft.due?.minute.map { labels.time($0) }
        }
    }
}
