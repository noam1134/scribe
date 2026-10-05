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

/// Whether the system lets Scribe show notifications (spec §13: when
/// denied, the app works normally and Settings explains how to enable).
enum NotificationPermission: Equatable {
    /// Never asked. Scribe asks the first time there is something to
    /// notify while the app is in front.
    case notDetermined
    /// Turned off in the system's Settings.
    case denied
    case allowed
}

/// Local notifications on iPhone and Mac (spec §11): keeps the pending
/// requests equal to `NotificationPlanner`'s plan, and handles taps and the
/// Done / +1 hour / Tomorrow buttons in the app process.
///
/// It re-plans after every store change — local writes, CloudKit imports and
/// writes by other processes all bump the store, which this object observes —
/// and on app activation, at midnight, on a time-zone change and when the
/// settings change.
///
/// For the Settings screen (Phase 6):
/// - `settings` — bindable (`@Bindable var notifications = NotificationCoordinator.shared`,
///   then `$notifications.settings.isEnabled`, `.morningSummaryEnabled`,
///   `.morningSummaryMinute`). Saved per device and re-planned on change.
/// - `permission` — `.denied` means "turned off in Settings": show
///   `systemSettingsURL`. Refreshed on activation.
/// - `requestPermission()` — for an explicit "Turn On" when `.notDetermined`.
@MainActor
@Observable
final class NotificationCoordinator: NSObject {
    static let shared = NotificationCoordinator()

    /// Per-device preferences, stored in `UserDefaults.standard` (never synced).
    var settings: NotificationSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            setNeedsReschedule()
        }
    }

    private(set) var permission: NotificationPermission = .notDetermined

    /// Where the system keeps Scribe's notification switches.
    static var systemSettingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #endif
    }

    /// UI tests (`-uiTesting`) keep notifications off — no permission alert
    /// over the smoke tests — unless `-enableNotifications` is passed too.
    static var isActiveInThisRun: Bool {
        !StoreLoader.isUITesting || CommandLine.arguments.contains("-enableNotifications")
    }

    @ObservationIgnored private weak var loader: StoreLoader?
    @ObservationIgnored private var store: SwiftDataItemStore?
    /// The reschedule waiting to run; later requests fold into it.
    @ObservationIgnored private var queued: Task<Void, Never>?
    /// The most recent reschedule; the next one waits for it, so they never overlap.
    @ObservationIgnored private var latest: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.noamchuri.scribe", category: "notifications")

    private override init() {
        settings = NotificationSettings(from: .standard)
        super.init()
    }

    /// Call from `App.init`: the delegate must be set before launch finishes,
    /// or a tap that launches the app is lost.
    func install(loader: StoreLoader) {
        self.loader = loader
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(NotificationCategory.registered)
        guard Self.isActiveInThisRun else { return }
        observeSystemEvents()
        watch(loader)
    }

    /// Asks the system for permission, then re-plans.
    func requestPermission() async {
        await askForPermission()
        setNeedsReschedule(after: .zero)
    }

    // MARK: Store

    /// Starts once the loader has a store (also after Retry).
    private func watch(_ loader: StoreLoader) {
        let state = withObservationTracking { loader.state } onChange: { [weak self, weak loader] in
            Task { @MainActor in
                guard let self, let loader else { return }
                self.watch(loader)
            }
        }
        if case .ready(let store) = state { start(store) }
    }

    private func start(_ store: SwiftDataItemStore) {
        guard self.store !== store else { return }
        self.store = store
        setNeedsReschedule(after: .zero)
    }

    /// The store, opening it if the app was launched in the background just
    /// to handle a notification button (no window, so nothing opened it).
    private func openStore() -> SwiftDataItemStore? {
        guard let loader else { return nil }
        if case .loading = loader.state { loader.load() }
        guard case .ready(let store) = loader.state else { return nil }
        start(store)
        return store
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
                MainActor.assumeIsolated { self?.setNeedsReschedule() }
            })
        }
    }

    // MARK: Scheduling

    /// Coalesces bursts (a save also posts a remote-change notice, which
    /// refreshes the store again) into one pass.
    private func setNeedsReschedule(after delay: Duration = .milliseconds(300)) {
        guard Self.isActiveInThisRun, store != nil, queued == nil else { return }
        let previous = latest
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            await previous?.value
            await self?.reschedule()
        }
        queued = task
        latest = task
    }

    /// Re-plans now and returns when the pending requests are up to date —
    /// for work that must finish before the app is suspended (a notification
    /// button, a background refresh task).
    func rescheduleNow() async {
        setNeedsReschedule(after: .zero)
        await latest?.value
    }

    private func reschedule() async {
        queued = nil
        guard let store else { return }
        // Reading inside the tracking block subscribes to the store: the next
        // write or refresh calls back here.
        let (items, categories) = withObservationTracking {
            (store.items(.all), store.categories)
        } onChange: { [weak self] in
            Task { @MainActor in self?.setNeedsReschedule() }
        }
        let planned = NotificationPlanner().plan(items: items, categories: categories, settings: settings, now: Date())

        await refreshPermission()
        if permission == .notDetermined, !planned.isEmpty, isAppActive {
            await askForPermission()
        }
        let wanted = permission == .allowed ? planned : []

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map {
            NotificationDiff.Pending(id: $0.identifier, fingerprint: $0.content.userInfo[PlannedNotification.UserInfoKey.fingerprint] as? String)
        }
        let diff = NotificationDiff(pending: pending, planned: wanted)
        if !diff.remove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.remove)
        }
        for planned in diff.add {
            do {
                try await center.add(planned.request)
            } catch {
                log.error("Couldn’t schedule \(planned.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        await removeDeliveredAlertsOfClosedItems(store)

        log.notice("Notifications: \(wanted.count, privacy: .public) planned, +\(diff.add.count, privacy: .public) −\(diff.remove.count, privacy: .public), permission \(String(describing: self.permission), privacy: .public)")
        #if DEBUG
        log.notice("Pending: \(wanted.map(\.id).joined(separator: ", "), privacy: .public)")
        #endif
    }

    /// An alert still in Notification Center for an item that has since been
    /// completed or deleted (here or on another device) is cleared.
    private func removeDeliveredAlertsOfClosedItems(_ store: SwiftDataItemStore) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        let closed = delivered.filter { identifier in
            guard let itemID = PlannedNotification.itemID(fromIdentifier: identifier) else { return false }
            return store.item(itemID)?.isDone ?? true
        }
        if !closed.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: closed)
        }
    }

    // MARK: Permission

    private var isAppActive: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        NSApplication.shared.isActive
        #endif
    }

    private func askForPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Permission request failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshPermission()
    }

    private func refreshPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        permission = switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed // authorized, provisional, ephemeral
        }
    }

    // MARK: Responses

    private func handle(actionIdentifier: String, link: DeepLink?, itemID: UUID?) async {
        if let action = NotificationAction(rawValue: actionIdentifier) {
            guard let itemID, let store = openStore() else { return }
            do {
                try action.perform(itemID: itemID, store: store, now: Date(), calendar: .autoupdatingCurrent)
            } catch {
                log.error("\(action.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            // Finish before returning: the system may suspend the app as soon
            // as the response is handled.
            await rescheduleNow()
        } else if actionIdentifier == UNNotificationDefaultActionIdentifier, let link {
            // Routed like any scribe:// link (the item, or Upcoming for the summary).
            loader?.pendingLink = link
        }
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
