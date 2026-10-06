import ScribeCore
import SwiftUI

/// A row's checklist progress, "☑ 2/5", for its secondary line; takes the
/// line's font and color.
struct ChecklistBadge: View {
    let progress: ChecklistProgress

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checklist")
            Text(progress.text)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.spokenText)
        .accessibilityIdentifier("checklistProgress")
    }
}
