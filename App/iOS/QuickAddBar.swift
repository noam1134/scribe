import SwiftUI

/// The glass capsule above the tab bar (spec §8). Tapping it opens the
/// composer, filed into the category on screen if there is one.
struct QuickAddBar: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button {
            router.compose(in: router.visibleCategoryID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                if placement != .inline {
                    Text("Add a task or note")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a task or note")
        .accessibilityIdentifier("quickAddBar")
    }
}
