import ScribeCore
import UserNotifications

extension PlannedNotification {
    /// The request handed to the notification center. The calendar trigger
    /// has no time zone, so it fires at the item's wall-clock time wherever
    /// the device is (spec §5.2).
    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = threadID
        content.categoryIdentifier = category.rawValue
        var info = [
            UserInfoKey.fingerprint: fingerprint,
            UserInfoKey.link: link.url.absoluteString,
        ]
        if let itemID { info[UserInfoKey.itemID] = itemID.uuidString }
        content.userInfo = info
        let trigger = UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

extension NotificationCategory {
    /// Registered once at launch; decides the buttons each notification shows.
    static var registered: Set<UNNotificationCategory> {
        Set(allCases.map { category in
            UNNotificationCategory(identifier: category.rawValue, actions: category.actions.map(\.button), intentIdentifiers: [])
        })
    }
}

extension NotificationAction {
    /// Handled in the background: Scribe doesn't come to the front and the
    /// phone needn't be unlocked, as in Reminders.
    var button: UNNotificationAction {
        UNNotificationAction(identifier: rawValue, title: title, options: [], icon: UNNotificationActionIcon(systemImageName: symbolName))
    }

    private var symbolName: String {
        switch self {
        case .done: "checkmark.circle"
        case .inAnHour: "clock.arrow.circlepath"
        case .tomorrow: "sunrise"
        }
    }
}
