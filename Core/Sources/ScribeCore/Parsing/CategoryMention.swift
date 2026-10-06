import Foundation

/// A category named in plain words at the end of quick-add text: "… in
/// Thailand", "… for work", "… to my Thailand list", "… on the Work list";
/// Hebrew "… בתאילנד", "… לעבודה", "… ברשימת עבודה".
///
/// Names match ignoring case, diacritics and emoji, word by word: the whole
/// name first, else whole words of it ("for work" → "Work Projects").
/// "homework" never matches "work". Two categories at the best level are
/// ambiguous: no match.
enum CategoryMention {
    struct Match: Equatable {
        /// Words of the text the mention takes, counted from its end.
        let length: Int
        let categoryID: UUID
    }

    /// The mention that ends `words`, if any.
    static func trailing(in words: ArraySlice<String>, categories: [CategorySnapshot]) -> Match? {
        // Words that fold to nothing (an emoji, a dash) ride along.
        let keys = words.indices.compactMap { index -> (index: Int, key: String)? in
            let key = fold(words[index])
            return key.isEmpty ? nil : (index, key)
        }
        guard !keys.isEmpty else { return nil }

        var candidates: [(match: Match, isWholeName: Bool)] = []
        for category in categories {
            let name = nameWords(category.name)
            guard !name.isEmpty else { continue }
            for found in matches(of: name, atEndOf: keys.map(\.key)) {
                let start = keys[keys.count - found.keyCount].index
                let match = Match(length: words.endIndex - start, categoryID: category.id)
                candidates.append((match, found.isWholeName))
            }
        }
        let best = candidates.contains(where: \.isWholeName) ? candidates.filter(\.isWholeName) : candidates
        guard let first = best.first, best.allSatisfy({ $0.match.categoryID == first.match.categoryID }) else { return nil }
        return best.map(\.match).max { $0.length < $1.length }
    }

    /// A category name as comparison words: no emoji, case or diacritics.
    static func nameWords(_ name: String) -> [String] {
        name.split(whereSeparator: \.isWhitespace).map(fold).filter { !$0.isEmpty }
    }

    static func fold(_ word: some StringProtocol) -> String {
        String(word.filter { !isEmoji($0) })
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: edgeMarks)
    }

    // MARK: Patterns

    private struct Found {
        /// Keys the mention spans, from the end.
        let keyCount: Int
        let isWholeName: Bool
    }

    private static let prepositions: Set<String> = ["in", "for", "on", "at", "under", "into", "to"]
    /// "to Thailand" is a destination, not a filing: "to" needs "… list".
    private static let needListWord: Set<String> = ["to", "into"]
    private static let determiners: Set<String> = ["my", "the", "our"]
    private static let listWords: Set<String> = ["list", "category"]
    private static let hebrewListWords: Set<String> = [
        "ברשימת", "לרשימת", "ברשימה", "לרשימה", "בקטגוריה", "לקטגוריה", "בקטגוריית", "לקטגוריית",
    ]
    private static let hebrewPrefixes: Set<Character> = ["ב", "ל"]

    private static func matches(of name: [String], atEndOf keys: [String]) -> [Found] {
        var found: [Found] = []
        for run in runs(of: name, atEndOf: keys) {
            let before = keys[..<(keys.count - run.count)]
            if run.isHebrewPrefixed {
                found.append(Found(keyCount: run.count, isWholeName: true))
            } else {
                let leads = englishLead(before, hasListWord: false) + hebrewLead(before)
                found += leads.map { Found(keyCount: run.count + $0, isWholeName: run.isWholeName) }
            }
        }
        // "… my Thailand list": the list word after the name.
        if let last = keys.last, listWords.contains(last) {
            let rest = Array(keys.dropLast())
            for run in runs(of: name, atEndOf: rest) where !run.isHebrewPrefixed {
                let leads = englishLead(rest[..<(rest.count - run.count)], hasListWord: true)
                found += leads.map { Found(keyCount: run.count + 1 + $0, isWholeName: run.isWholeName) }
            }
        }
        return found
    }

    private struct Run {
        let count: Int
        let isWholeName: Bool
        /// The run's first word carries a Hebrew ב/ל ("בתאילנד") instead of a
        /// separate preposition.
        let isHebrewPrefixed: Bool
    }

    /// Ways the end of `keys` spells the name, or a whole-word run of it.
    /// With a Hebrew ב/ל — no preposition to anchor it — only the whole name
    /// counts: "לספר" ("to tell") is not "בית ספר".
    private static func runs(of name: [String], atEndOf keys: [String]) -> [Run] {
        var runs: [Run] = []
        for count in 1...min(name.count, keys.count) {
            let tail = Array(keys.suffix(count))
            for start in 0...(name.count - count) {
                let part = Array(name[start..<(start + count)])
                let isWholeName = count == name.count
                guard Array(tail.dropFirst()) == Array(part.dropFirst()) else { continue }
                if matchesWord(tail[0], part[0]) {
                    runs.append(Run(count: count, isWholeName: isWholeName, isHebrewPrefixed: false))
                } else if isWholeName, let unprefixed = droppingHebrewPrefix(tail[0]), matchesWord(unprefixed, part[0]) {
                    runs.append(Run(count: count, isWholeName: true, isHebrewPrefixed: true))
                }
            }
        }
        return runs
    }

    /// Hebrew drops the article after ב/ל ("בבית" is ב + "הבית"), and adds
    /// it to a name that lacks it ("לרשימת הקניות").
    private static func matchesWord(_ word: String, _ nameWord: String) -> Bool {
        if word == nameWord { return true }
        if nameWord.hasPrefix("ה"), word == String(nameWord.dropFirst()) { return true }
        if word.hasPrefix("ה"), String(word.dropFirst()) == nameWord { return true }
        return false
    }

    private static func droppingHebrewPrefix(_ word: String) -> String? {
        guard let first = word.first, hebrewPrefixes.contains(first) else { return nil }
        var rest = word.dropFirst()
        if let mark = rest.first, mark == "-" || mark == "\u{05BE}" { rest = rest.dropFirst() }
        return rest.isEmpty ? nil : String(rest)
    }

    /// "in", "at", "for my", "to the … list": how many keys before the name
    /// introduce it.
    private static func englishLead(_ keys: ArraySlice<String>, hasListWord: Bool) -> [Int] {
        var leads: [Int] = []
        func isPreposition(_ word: String?) -> Bool {
            guard let word, prepositions.contains(word) else { return false }
            return hasListWord || !needListWord.contains(word)
        }
        if isPreposition(keys.last) { leads.append(1) }
        if let last = keys.last, determiners.contains(last), isPreposition(keys.dropLast().last) { leads.append(2) }
        return leads
    }

    /// "ברשימת", "ברשימה של".
    private static func hebrewLead(_ keys: ArraySlice<String>) -> [Int] {
        guard let last = keys.last else { return [] }
        if hebrewListWords.contains(last) { return [1] }
        if last == "של", let word = keys.dropLast().last, hebrewListWords.contains(word) { return [2] }
        return []
    }

    // MARK: Characters

    private static let edgeMarks = CharacterSet.punctuationCharacters
        .union(.symbols)
        .union(.whitespaces)
        .subtracting(CharacterSet(charactersIn: "#"))

    /// "🇹🇭", "💼", "❤️", "1️⃣" — but not a plain digit.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        return first.properties.isEmoji && scalars.count > 1
    }
}
