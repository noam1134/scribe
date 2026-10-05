import ScribeCore
import SwiftUI

extension CategorySnapshot {
    /// The category's palette color (spec §5.1).
    var color: Color {
        switch colorName {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        case "gray": .gray
        default: .blue
        }
    }

    /// "🇹🇭 Thailand", or just the name without an emoji.
    var displayName: String { emoji.isEmpty ? name : "\(emoji) \(name)" }
}

extension View {
    /// Lays the view out in the direction of `text` itself — right-to-left
    /// for Hebrew, left-to-right otherwise — whatever the system language
    /// (spec §9.4).
    func layoutDirection(of text: String) -> some View {
        environment(\.layoutDirection, TextDirection.of(text) == .rightToLeft ? .rightToLeft : .leftToRight)
    }
}
