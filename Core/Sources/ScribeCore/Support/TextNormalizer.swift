import Foundation

enum TextNormalizer {
    /// Comparison key that ignores case, diacritics and whitespace:
    /// "Thai Land", "thailand" and "THAILAND" share one key.
    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { !$0.isWhitespace }
    }
}
