import ScribeCore
import UserNotifications

/// `UNUserNotificationCenter` behind the scheduler's `NotificationCenterClient`.
@MainActor
final class SystemNotificationCenter: NotificationCenterClient {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed // authorized, provisional, ephemeral
        }
    }

    func requestAuthorization() async throws -> NotificationPermission {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    func pending() async -> [NotificationDiff.Pending] {
        await center.pendingNotificationRequests().map {
            NotificationDiff.Pending(id: $0.identifier, fingerprint: $0.content.userInfo[PlannedNotification.UserInfoKey.fingerprint] as? String)
        }
    }

    func add(_ request: PlannedNotification) async throws {
        try await center.add(request.request)
    }

    func removePending(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    func removeDelivered(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

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
