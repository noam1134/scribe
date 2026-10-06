import Foundation

/// A category — and a cleaner title — that the on-device model proposed for
/// a quick-add title the parser couldn't file. The app asks the model; this
/// checks its answer, so a made-up category or a rewritten title never
/// reaches the store.
public struct CategorySuggestion: Equatable, Sendable {
    public let categoryID: UUID
    /// The title to save: the model's, when it is a fair cut of the
    /// original, else the original.
    public let title: String

    public init(categoryID: UUID, title: String) {
        self.categoryID = categoryID
        self.title = title
    }

    /// - Parameters:
    ///   - categoryName: the model's pick; nil or a name that isn't exactly
    ///     one category means no suggestion.
    ///   - suggestedTitle: the model's title. Used only when it is a
    ///     whole-word run of `title` keeping at least half its words, in the
    ///     user's own spelling.
    ///   - title: what the model was given — the parser's title.
    public static func checked(categoryName: String?, suggestedTitle: String?, for title: String, categories: [CategorySnapshot]) -> CategorySuggestion? {
        guard let name = categoryName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let exact = categories.filter { $0.name == name }
        let folded = CategoryMention.nameWords(name)
        let candidates = exact.isEmpty ? categories.filter { CategoryMention.nameWords($0.name) == folded } : exact
        guard candidates.count == 1, let category = candidates.first else { return nil }
        let cut = suggestedTitle.flatMap { piece(of: title, named: $0) }
        return CategorySuggestion(categoryID: category.id, title: cut ?? title)
    }

    /// The words of `title` that `suggested` names, case- and
    /// diacritic-insensitively, on word boundaries.
    static func piece(of title: String, named suggested: String) -> String? {
        let wanted = suggested.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !wanted.isEmpty,
              let range = title.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let startsWord = range.lowerBound == title.startIndex || title[title.index(before: range.lowerBound)].isWhitespace
        let endsWord = range.upperBound == title.endIndex || !(title[range.upperBound].isLetter || title[range.upperBound].isNumber)
        guard startsWord, endsWord else { return nil }
        let piece = String(title[range])
        let wordCount = { (text: String) in text.split(whereSeparator: \.isWhitespace).count }
        guard wordCount(piece) * 2 >= wordCount(title) else { return nil }
        return range.lowerBound == title.startIndex ? piece : RequestPhrases.capitalizingFirstWord(piece)
    }
}
