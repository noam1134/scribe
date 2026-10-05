import Foundation
import Observation
import OSLog
import ScribeCore
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Local notifications on iPhone and Mac (spec §11). The app's side of
/// `NotificationScheduler` (Core), which decides and schedules: this object
/// is the `UNUserNotificationCenterDelegate`, hands the scheduler the store
/// once it's open, re-plans on activation, at midnight and on a time-zone
/// change, and logs.
///
/// For the Settings screen (Phase 6):
/// - `settings` — bindable (`@Bindable var notifications = NotificationCoordinator.shared`,
///   then `$notifications.settings.isEnabled`, `.morningSummaryEnabled`,
///   `.morningSummaryMinute`). Saved per device and re-planned on change.
/// - `permission` — `.denied` means "turned off in Settings": show
///   `systemSettingsURL`. Refreshed on every pass (activation included).
/// - `requestPermission()` — for an explicit "Turn On" (call it when the
///   switch is turned on).
///
/// For background work (refresh task, intents run in the app process):
/// `rescheduleNow()` opens the store if needed and returns when done.
@MainActor
@Observable
final class NotificationCoordinator: NSObject {
    static let shared = NotificationCoordinator()

    /// Per-device preferences in the App Group's defaults (never synced).
    var settings: NotificationSettings {
        get { scheduler.settings }
        set { scheduler.settings = newValue }
    }

    var permission: NotificationPermission { scheduler.permission }

    /// Scribe's own page in the system's notification settings.
    static var systemSettingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "com.noamchuri.scribe")")
        #endif
    }

    /// UI tests (`-uiTesting`) keep notifications off — no permission alert
    /// over the smoke tests — unless `-enableNotifications` is passed too.
    static var isActiveInThisRun: Bool {
        !StoreLoader.isUITesting || CommandLine.arguments.contains("-enableNotifications")
    }

    @ObservationIgnored private let scheduler: NotificationScheduler
    @ObservationIgnored private let link: LoaderLink
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.noamchuri.scribe", category: "notifications")

    private override init() {
        let link = LoaderLink()
        self.link = link
        scheduler = NotificationScheduler(
            center: SystemNotificationCenter(),
            defaults: NotificationSettings.appGroupDefaults,
            openStore: { link.openStore() },
            mayAskForPermission: { Self.isAppActive }
        )
        super.init()
        scheduler.onEvent = { [log] event in Self.log(event, to: log) }
    }

    /// Call from `App.init`: the delegate must be set before launch finishes,
    /// or a tap that launches the app is lost.
    func install(loader: StoreLoader) {
        link.loader = loader
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(NotificationCategory.registered)
        guard Self.isActiveInThisRun else { return }
        observeSystemEvents()
        watch(loader)
    }

    func requestPermission() async {
        // Settings' switch in a UI-test run: no system prompt over the tests.
        guard Self.isActiveInThisRun else { return }
        await scheduler.requestPermission()
    }

    /// Re-plans now, opening the store first if nothing has, and returns when
    /// the pending requests are up to date — for work that must finish
    /// before the app is suspended.
    func rescheduleNow() async {
        guard Self.isActiveInThisRun else { return }
        await scheduler.rescheduleNow()
    }

    // MARK: Store and system events

    /// Hands over the store once the loader has one (also after Retry).
    private func watch(_ loader: StoreLoader) {
        let state = withObservationTracking { loader.state } onChange: { [weak self, weak loader] in
            Task { @MainActor in
                guard let self, let loader else { return }
                self.watch(loader)
            }
        }
        if case .ready(let store) = state { scheduler.attach(store) }
    }

    private func observeSystemEvents() {
        #if os(iOS)
        let didBecomeActive = UIApplication.didBecomeActiveNotification
        #else
        let didBecomeActive = NSApplication.didBecomeActiveNotification
        #endif
        // Activation: permission may have changed in Settings, and the
        // seven-day summary window moves with the clock.
        for name in [didBecomeActive, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduler.setNeedsReschedule() }
            })
        }
    }

    private static var isAppActive: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        NSApplication.shared.isActive
        #endif
    }

    // MARK: Responses

    private func handle(actionIdentifier: String, link: DeepLink?, itemID: UUID?) async {
        if let action = NotificationAction(rawValue: actionIdentifier) {
            guard let itemID else {
                log.error("\(action.rawValue, privacy: .public) arrived without an item")
                return
            }
            await scheduler.perform(action, itemID: itemID)
        } else if actionIdentifier == UNNotificationDefaultActionIdentifier, let link {
            // Routed like any scribe:// link (the item, or Upcoming for the summary).
            self.link.loader?.pendingLink = link
        }
    }

    // MARK: Log

    private static func log(_ event: NotificationScheduler.Event, to log: Logger) {
        switch event {
        case let .rescheduled(planned, added, removed, permission):
            log.notice("Notifications: \(planned.count, privacy: .public) planned, +\(added, privacy: .public) −\(removed, privacy: .public), permission \(String(describing: permission), privacy: .public)")
            #if DEBUG
            log.notice("Pending: \(planned.joined(separator: ", "), privacy: .public)")
            #endif
        case let .schedulingFailed(id, message):
            log.error("Couldn’t schedule \(id, privacy: .public): \(message, privacy: .public)")
        case let .permissionRequestFailed(message):
            log.error("Permission request failed: \(message, privacy: .public)")
        case let .actionFailed(action, itemID, message):
            log.error("\(action.rawValue, privacy: .public) on \(itemID, privacy: .public) failed: \(message, privacy: .public)")
        case let .actionDropped(action, itemID):
            log.error("\(action.rawValue, privacy: .public) on \(itemID, privacy: .public) dropped: the store couldn’t be opened")
        case .storeUnavailable:
            log.error("Couldn’t re-plan notifications: the store couldn’t be opened")
        }
    }
}

/// The loader, for opening the one store in a background launch (a
/// notification button or a refresh task, with no window to open it).
@MainActor
private final class LoaderLink {
    weak var loader: StoreLoader?

    func openStore() -> (any ItemStore)? {
        guard let loader else { return nil }
        if case .loading = loader.state { loader.load() }
        guard case .ready(let store) = loader.state else { return nil }
        return store
    }
}

extension NotificationCoordinator: UNUserNotificationCenterDelegate {
    /// Alerts show while the app is open too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let info = request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        let link = (info[PlannedNotification.UserInfoKey.link] as? String)
            .flatMap(URL.init(string:))
            .flatMap(DeepLink.init(url:))
        let itemID = (info[PlannedNotification.UserInfoKey.itemID] as? String).flatMap(UUID.init(uuidString:))
            ?? PlannedNotification.itemID(fromIdentifier: request.identifier)
        nonisolated(unsafe) let finished = completionHandler
        Task { @MainActor in
            await self.handle(actionIdentifier: actionIdentifier, link: link, itemID: itemID)
            finished() // on the main thread, where UIKit expects it
        }
    }
}
