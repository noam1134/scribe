import Foundation

/// Leading request phrases dropped from a quick-add title: "remind me to
/// call mom" files "Call mom", "תזכיר לי שצריך לקנות חלב" files "לקנות חלב".
///
/// A bare "add" stays: "Add tests for the parser" is itself the task. It
/// goes only before a reminder word ("add a task to …", "add reminder: …").
enum RequestPhrases {
    /// The title without its leading request phrases, or nil when it has
    /// none or nothing would be left. An English title then starts with a
    /// capital ("Call mom"), unless its first word is cased on purpose
    /// ("iPhone").
    static func cleaned(_ title: String) -> String? {
        let (words, dropped) = droppingPhrases(title)
        guard dropped, !words.isEmpty else { return nil }
        return capitalizingFirstWord(words.joined(separator: " "))
    }

    /// Nothing but request phrases ("remind me"), or nothing at all.
    static func isEmptyRequest(_ title: String) -> Bool {
        droppingPhrases(title).words.isEmpty
    }

    private static func droppingPhrases(_ title: String) -> (words: [String], dropped: Bool) {
        var words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        var dropped = false
        while let phrase = leadingPhrase(in: words) {
            words.removeFirst(phrase.count)
            if phrase.isHebrew { dropClauseMarker(&words) }
            while let first = words.first, separators.contains(first) { words.removeFirst() }
            dropped = true
        }
        return (words, dropped)
    }

    /// Upper-cases the first letter when the first word is all lower case.
    static func capitalizingFirstWord(_ title: String) -> String {
        guard let first = title.first, first.isLowercase else { return title }
        let firstWord = title.prefix { !$0.isWhitespace }
        guard !firstWord.contains(where: \.isUppercase) else { return title }
        return first.uppercased() + title.dropFirst()
    }

    private struct Phrase {
        let words: [String]
        let isHebrew: Bool
        var count: Int { words.count }
    }

    private static func leadingPhrase(in words: [String]) -> Phrase? {
        let keys = words.prefix(longestPhrase).map(key)
        return phrases.first { phrase in
            phrase.count <= keys.count && zip(phrase.words, keys).allSatisfy { $0 == $1 }
        }
    }

    /// "תזכיר לי שצריך…": the ש that opens the clause goes with the phrase,
    /// but only when what follows is clearly a clause ("שאני", "שהפגישה",
    /// "ש-") — "שולחן" keeps its ש.
    private static func dropClauseMarker(_ words: inout [String]) {
        guard let first = words.first, first.hasPrefix("ש") else { return }
        let rest = String(first.dropFirst())
        if rest.isEmpty || rest == "-" || rest == "־" {
            words.removeFirst()
        } else if rest.hasPrefix("-") || rest.hasPrefix("־") {
            words[0] = String(rest.dropFirst())
        } else if clauseOpeners.contains(rest) || (rest.hasPrefix("ה") && rest.count >= 3) {
            words[0] = rest
        }
    }

    /// Lower-cased, without diacritics, with one kind of apostrophe and no
    /// trailing comma: "Don’t" and "please," match their phrases.
    private static func key(_ word: String) -> String {
        var key = word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
        while key.count > 1, key.hasSuffix(",") { key.removeLast() }
        return key
    }

    private static let separators: Set<String> = [":", "-", "\u{2013}", "\u{2014}", ",", "\u{05BE}"]

    /// Words a Hebrew clause opens with after its ש: "שאני צריך", "שמחר".
    private static let clauseOpeners: Set<String> = [
        "אני", "אנחנו", "אתה", "את", "הוא", "היא", "הם", "הן",
        "צריך", "צריכה", "צריכים", "יש", "אין", "לא", "מחר", "היום",
    ]

    private static let english: [[String]] = {
        var phrases: [[String]] = [
            ["remind", "me", "to"], ["remind", "me", "that"], ["remind", "me", "about"], ["remind", "me"],
            ["remember", "to"], ["remember", "that"],
            ["don't", "forget", "to"], ["don't", "forget", "that"], ["don't", "forget", "about"], ["don't", "forget"],
            ["dont", "forget", "to"], ["dont", "forget"],
            ["do", "not", "forget", "to"], ["do", "not", "forget"],
            ["i", "need", "to"], ["i", "have", "to"], ["i've", "got", "to"], ["i", "gotta"], ["i", "must"], ["i", "should"],
            ["we", "need", "to"], ["we", "have", "to"], ["need", "to"], ["have", "to"],
            ["todo:"], ["to-do:"], ["to", "do:"], ["todo", ":"], ["todo", "-"],
            ["reminder:"], ["reminder", "to"],
            ["please"],
            ["add:"],
        ]
        for article in [[], ["a"], ["an"], ["new"], ["a", "new"]] {
            for noun in ["reminder", "task", "todo", "to-do", "note", "item"] {
                phrases.append(["add"] + article + [noun + ":"])
                for tail in [["to"], ["that"], [":"], []] {
                    phrases.append(["add"] + article + [noun] + tail)
                }
            }
        }
        return phrases
    }()

    private static let hebrew: [[String]] = [
        ["תזכיר", "לי"], ["תזכירי", "לי"], ["תזכירו", "לי"], ["להזכיר", "לי"],
        ["תזכורת:"], ["תזכורת", ":"], ["תזכורת", "-"],
        ["לא", "לשכוח"], ["אל", "תשכח"], ["אל", "תשכחי"], ["אל", "תשכחו"], ["לזכור"],
        ["אני", "צריך"], ["אני", "צריכה"], ["אנחנו", "צריכים"], ["צריך"], ["צריכה"], ["צריכים"],
        ["בבקשה"],
    ]

    /// Longest first, so "remind me to" wins over "remind me".
    private static let phrases: [Phrase] = (english.map { Phrase(words: $0, isHebrew: false) } + hebrew.map { Phrase(words: $0, isHebrew: true) })
        .sorted { $0.count > $1.count }

    private static let longestPhrase = phrases.map(\.count).max() ?? 0
}
