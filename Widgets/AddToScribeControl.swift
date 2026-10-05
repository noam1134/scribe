import AppIntents
import SwiftUI
import WidgetKit

/// "Add to Scribe" for Control Center, the Lock Screen and the Action Button
/// (spec §8): opens the composer, in a category if one is configured.
struct AddToScribeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: WidgetKinds.addControl, intent: AddControlConfiguration.self) { configuration in
            // A deleted category falls back to plain "Add to Scribe".
            let category = configuration.category.flatMap { $0.isDeleted ? nil : $0 }
            ControlWidgetButton(action: OpenQuickAddIntent(category: category)) {
                Label(category.map { "Add to \($0.name)" } ?? "Add to Scribe", systemImage: "plus.circle")
            }
        }
        .displayName("Add to Scribe")
        .description("Opens Scribe’s quick-add composer.")
    }
}

struct AddControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Add to Scribe"

    @Parameter(title: "Category", description: "Leave empty to pick one while adding.")
    var category: CategoryEntity?

    init() {}
}
