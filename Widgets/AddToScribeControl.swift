import AppIntents
import SwiftUI
import WidgetKit

/// "Add to Scribe" for Control Center, the Lock Screen and the Action Button
/// (spec §8): opens the composer.
///
/// Static, not intent-configured: on the iPhone the system gave the
/// configured Control no intent (`ControlError.intentConfigurationNotFound`),
/// so it rendered nothing and did nothing. Controls already placed keep
/// their kind and start working.
struct AddToScribeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.addControl) {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Add to Scribe", systemImage: "plus.circle")
            }
        }
        .displayName("Add to Scribe")
        .description("Opens Scribe’s quick-add composer.")
    }
}
