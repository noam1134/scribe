import ScribeCore
import SwiftUI

/// The chips for what the parser understood — tap one to undo it — or an
/// example when there are none (spec §8). Every quick-add surface shows it;
/// the caller picks the button style (glass over content, bordered inside
/// a glass panel — never glass on glass, spec §9.1).
struct QuickAddChipRow: View {
    let composer: QuickAddComposer
    let live: QuickAddComposer.LiveParse

    var body: some View {
        if !live.chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        ForEach(live.chips) { chip in
                            Button { composer.dismiss(chip) } label: {
                                Label(chip.label, systemImage: Self.icon(for: chip.kind))
                            }
                            .accessibilityHint("Removes this and keeps the text in the title")
                        }
                    }
                }
            }
            .scrollClipDisabled() // clipping draws a grey band behind the glass chips
        } else {
            Text("Try \u{201C}call mom tomorrow 9am #family\u{201D}")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    static func icon(for kind: TokenKind) -> String {
        switch kind {
        case .category: "folder"
        case .kind: "note.text"
        case .date: "calendar"
        case .time: "clock"
        }
    }
}

/// Where the item goes. One tap picks; a typed `#tag` picks for you; a typed
/// unknown `#name` offers to create it. No Inbox here (spec §19).
struct QuickAddCategoryRow: View {
    let composer: QuickAddComposer
    let live: QuickAddComposer.LiveParse
    /// Runs a store write and shows a refusal.
    let perform: @MainActor (() throws -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(live.categories) { category in
                        let picked = category.id == live.categoryID
                        Button {
                            composer.select(category.id)
                        } label: {
                            Label {
                                Text(category.displayName)
                                    .fontWeight(picked ? .semibold : .regular)
                            } icon: {
                                Image(systemName: picked ? "checkmark.circle.fill" : "circle.fill")
                                    .foregroundStyle(category.color)
                            }
                        }
                        .accessibilityAddTraits(picked ? .isSelected : [])
                        .accessibilityIdentifier("pickCategory-\(category.name)")
                    }
                    if let name = live.unknownCategoryName {
                        Button("New category \u{201C}\(name)\u{201D}", systemImage: "plus") {
                            perform { try composer.createUnknownCategory() }
                        }
                        .accessibilityIdentifier("newCategoryChip")
                    }
                }
            }
            .scrollClipDisabled()
            if live.categories.isEmpty && live.unknownCategoryName == nil {
                hint("Type #name to create a category")
            } else if live.draft.isValid && live.categoryID == nil {
                hint("Pick a category")
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("categoryHint")
    }
}
