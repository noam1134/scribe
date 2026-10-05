import AppIntents
import SwiftUI
import WidgetKit

/// "Add to Scribe" for Control Center, the Lock Screen and the Action Button
/// (spec §8): opens the composer, in a category if one is configured.
struct AddToScribeControl: ControlWidget {
    static let kind = "com.noamchuri.scribe.add"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: AddControlConfiguration.self) { configuration in
            ControlWidgetButton(action: OpenQuickAddIntent(category: configuration.category)) {
                Label(configuration.category.map { "Add to \($0.name)" } ?? "Add to Scribe", systemImage: "plus.circle")
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
