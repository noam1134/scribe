import Foundation

/// The buttons on an item's notification (spec §11). They change the item
/// itself, so the change syncs like any other edit.
public enum NotificationAction: String, CaseIterable, Sendable {
    case done = "scribe.action.done"
    case inAnHour = "scribe.action.inAnHour"
    case tomorrow = "scribe.action.tomorrow"

    /// Button title.
    public var title: String {
        switch self {
        case .done: "Done"
        case .inAnHour: "+1 Hour"
        case .tomorrow: "Tomorrow"
        }
    }
}
