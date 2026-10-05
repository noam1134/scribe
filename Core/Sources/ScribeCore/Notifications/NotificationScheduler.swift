import Foundation
import Observation

/// Whether the system lets Scribe show notifications (spec §13: when
/// denied, the app works normally and Settings explains how to enable).
public enum NotificationPermission: Equatable, Sendable {
    /// Never asked. Scribe asks the first time there is something to
    /// notify while the app is in front.
    case notDetermined
    /// Turned off in the system's Settings.
    case denied
    /// Authorized, provisional or ephemeral.
    case allowed
}

/// The parts of the system notification center the scheduler uses. The app
/// adapts `UNUserNotificationCenter`; tests use an in-memory fake.
@MainActor
public protocol NotificationCenterClient: AnyObject {
    func authorization() async -> NotificationPermission
    /// Shows the system prompt (only while undetermined) and returns the result.
    func requestAuthorization() async throws -> NotificationPermission
    func pending() async -> [NotificationDiff.Pending]
    func add(_ request: PlannedNotification) async throws
    func removePending(_ identifiers: [String])
    func deliveredIdentifiers() async -> [String]
    func removeDelivered(_ identifiers: [String])
}

/// Keeps the pending notifications equal to `NotificationPlanner`'s plan
/// for the current store, settings and permission (spec §11, §12).
///
/// It watches the store with Observation, so every local write and every
/// `refresh()` (CloudKit import, write by another process) re-plans. Passes
/// are coalesced and never overlap; the permission prompt runs on its own,
/// so an unanswered prompt never holds a pass up.
@MainActor
@Observable
public final class NotificationScheduler {
    public enum Event: Equatable, Sendable {
        /// A pass finished: the ids now planned (in plan order) and what changed.
        case rescheduled(planned: [String], added: Int, removed: Int, permission: NotificationPermission)
        case schedulingFailed(id: String, message: String)
        case permissionRequestFailed(String)
        case actionFailed(NotificationAction, itemID: UUID, message: String)
        /// A notification button arrived but the store couldn't be opened.
        case actionDropped(NotificationAction, itemID: UUID)
        /// `rescheduleNow()` couldn't open the store.
        case storeUnavailable
    }

    /// Per-device preferences; saved and re-planned on every change.
    public var settings: NotificationSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            setNeedsReschedule()
        }
    }

    public private(set) var permission: NotificationPermission = .notDetermined

    /// Errors and passes, for the app's log.
    @ObservationIgnored public var onEvent: @MainActor (Event) -> Void = { _ in }

    @ObservationIgnored private let center: any NotificationCenterClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let planner: NotificationPlanner
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let coalescing: Duration
    @ObservationIgnored private let openStore: @MainActor () -> (any ItemStore)?
    @ObservationIgnored private let mayAskForPermission: @MainActor () -> Bool

    @ObservationIgnored private var store: (any ItemStore)?
    /// The pass waiting to run; later requests fold into it.
    @ObservationIgnored private var queued: Task<Void, Never>?
    /// The most recent pass; the next one waits for it.
    @ObservationIgnored private var latest: Task<Void, Never>?
    /// The open permission prompt, if any.
    @ObservationIgnored private var permissionRequest: Task<Void, Never>?

    /// - Parameters:
    ///   - openStore: Opens (or returns) the process's one store. Called
    ///     when work arrives before anything else opened it — a background
    ///     launch for a notification button or a refresh task.
    ///   - mayAskForPermission: True while the app is in front (the system
    ///     prompt makes no sense otherwise).
    public init(
        center: any NotificationCenterClient,
        defaults: UserDefaults,
        fallbackSettings: NotificationSettings = .platformDefault,
        planner: NotificationPlanner = NotificationPlanner(),
        now: @escaping @MainActor () -> Date = { Date() },
        coalescing: Duration = .milliseconds(300),
        openStore: @escaping @MainActor () -> (any ItemStore)?,
        mayAskForPermission: @escaping @MainActor () -> Bool
    ) {
        self.center = center
        self.defaults = defaults
        self.planner = planner
        self.now = now
        self.coalescing = coalescing
        self.openStore = openStore
        self.mayAskForPermission = mayAskForPermission
        settings = NotificationSettings(from: defaults, fallback: fallbackSettings)
    }

    /// Plans from `store` from now on (the UI opened it, or Retry did).
    public func attach(_ store: any ItemStore) {
        guard self.store !== store else { return }
        self.store = store
        setNeedsReschedule(after: .zero)
    }

    /// Re-plans soon (activation, a new day, a time-zone change).
    public func setNeedsReschedule() {
        setNeedsReschedule(after: coalescing)
    }

    /// Re-plans now and returns when the pending requests are up to date.
    /// Opens the store if nothing has yet, so it works in a background
    /// launch (refresh task, intent run in the app process).
    public func rescheduleNow() async {
        if store == nil {
            guard let opened = openStore() else {
                onEvent(.storeUnavailable)
                return
            }
            attach(opened)
        }
        setNeedsReschedule(after: .zero)
        await latest?.value
    }

    /// Shows the system prompt if it hasn't been answered, then re-plans.
    public func requestPermission() async {
        await askForPermission().value
    }

    /// A notification button: applies it to the item, then re-plans before
    /// returning — the system may suspend the app right after.
    public func perform(_ action: NotificationAction, itemID: UUID) async {
        guard let store = store ?? openStore() else {
            onEvent(.actionDropped(action, itemID: itemID))
            return
        }
        attach(store)
        do {
            try action.perform(itemID: itemID, store: store, now: now(), calendar: planner.calendar)
        } catch {
            onEvent(.actionFailed(action, itemID: itemID, message: error.localizedDescription))
        }
        await rescheduleNow()
    }

    /// Waits for the open prompt and the latest pass (tests).
    func waitUntilIdle() async {
        await permissionRequest?.value
        await latest?.value
    }

    // MARK: Passes

    private func setNeedsReschedule(after delay: Duration) {
        guard store != nil, queued == nil else { return }
        let previous = latest
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            await previous?.value
            await self?.reschedule()
        }
        queued = task
        latest = task
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
        let planned = planner.plan(items: items, categories: categories, settings: settings, now: now())

        permission = await center.authorization()
        if permission == .notDetermined, !planned.isEmpty, mayAskForPermission() {
            askForPermission() // answered later; that re-plans
        }
        let wanted = permission == .allowed ? planned : []

        let diff = NotificationDiff(pending: await center.pending(), planned: wanted)
        if !diff.remove.isEmpty {
            center.removePending(diff.remove)
        }
        for request in diff.add {
            do {
                try await center.add(request)
            } catch {
                onEvent(.schedulingFailed(id: request.id, message: error.localizedDescription))
            }
        }

        // An alert still in Notification Center for an item completed or
        // deleted since (here or on another device) is cleared.
        let closed = await center.deliveredIdentifiers().filter { identifier in
            guard let itemID = PlannedNotification.itemID(fromIdentifier: identifier) else { return false }
            return store.item(itemID)?.isDone ?? true
        }
        if !closed.isEmpty {
            center.removeDelivered(closed)
        }

        onEvent(.rescheduled(planned: wanted.map(\.id), added: diff.add.count, removed: diff.remove.count, permission: permission))
    }

    // MARK: Permission

    /// One prompt at a time; when it's answered, re-plan.
    @discardableResult
    private func askForPermission() -> Task<Void, Never> {
        if let permissionRequest { return permissionRequest }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                permission = try await center.requestAuthorization()
            } catch {
                onEvent(.permissionRequestFailed(error.localizedDescription))
                permission = await center.authorization()
            }
            permissionRequest = nil
            setNeedsReschedule(after: .zero)
        }
        permissionRequest = task
        return task
    }
}
