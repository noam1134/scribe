public enum CategoryPalette {
    public static let colorNames = [
        "red", "orange", "yellow", "green", "mint", "teal", "cyan",
        "blue", "indigo", "purple", "pink", "brown", "gray",
    ]
    public static let defaultColorName = "blue"

    /// The color for a new category: the first palette color no category
    /// uses yet, so a fresh list isn't all one color. Cycles once all are used.
    public static func suggestedColorName(avoiding used: [String]) -> String {
        colorNames.first { !used.contains($0) } ?? colorNames[used.count % colorNames.count]
    }
}
