import CloudKit
import CoreData
import Observation
import ScribeCore
import os
#if os(macOS)
import Security
#endif

private let logger = Logger(subsystem: "com.noamchuri.scribe", category: "sync")

/// What Settings shows about iCloud (spec §13, §18): the device's account,
/// and when sync last worked or why it failed. It records CloudKit's events
/// from the moment the app's store opens, so "Last synced" is known before
/// Settings is ever shown. The log is saved per device (standard defaults;
/// never synced).
@MainActor
@Observable
final class SyncMonitor {
    static let shared = SyncMonitor()

    private(set) var account: CloudAccountState = .checking
    private(set) var log: SyncLog

    /// Nil in UI-test runs: nothing is saved there.
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var container: CKContainer?
    @ObservationIgnored private var isStarted = false
    /// The check still running; a newer request replaces it.
    @ObservationIgnored private var accountCheck: Task<Void, Never>?
    @ObservationIgnored private var accountCheckNumber = 0
    /// The signed-in account's user record name, fetched once per account.
    @ObservationIgnored private var identity: String?

    private init() {
        if StoreLoader.isUITesting {
            // No iCloud in UI tests (an in-memory store).
            defaults = nil
            #if DEBUG
            let demo = SettingsDemo.sync ?? (.noAccount, SyncLog())
            #else
            let demo = (CloudAccountState.noAccount, SyncLog())
            #endif
            account = demo.0
            log = demo.1
        } else {
            defaults = .standard
            log = SyncLog(from: .standard)
        }
    }

    /// Starts recording; later calls do nothing. Called when the app's
    /// store opens (`AppProcess`) and by Settings.
    func start() {
        guard !isStarted, !StoreLoader.isUITesting else { return }
        isStarted = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            // Each event is posted when it starts and again when it ends.
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  let end = event.endDate,
                  let kind = SyncEventKind(event.type),
                  let outcome = SyncEvent(kind: kind, endDate: end, succeeded: event.succeeded, error: event.error as NSError?) else { return }
            MainActor.assumeIsolated { self?.record(outcome) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.identity = nil // maybe another account now
                self?.refreshAccount()
            }
        })
        // Also tells whether the log still describes this account.
        refreshAccount()
    }

    /// Asks CloudKit for the account again (start, Settings appearing, the
    /// app coming back from the system's settings, an account change). A
    /// newer request replaces one still running, so an older answer never
    /// overwrites a newer one.
    func refreshAccount() {
        guard !StoreLoader.isUITesting else { return }
        accountCheck?.cancel()
        accountCheckNumber += 1
        let number = accountCheckNumber
        accountCheck = Task { await checkAccount(number) }
    }

    private func checkAccount(_ number: Int) async {
        var state = CloudAccountState.unknown
        var identity = self.identity
        if let container = cloudKitContainer() {
            do {
                state = CloudAccountState(try await container.accountStatus())
                if state == .available, identity == nil {
                    identity = try await container.userRecordID().recordName
                }
            } catch {
                logger.error("Couldn't read the iCloud account: \(String(describing: error), privacy: .public)")
                if state != .available { state = .unknown }
            }
        }
        guard number == accountCheckNumber, !Task.isCancelled else { return }
        let previous = account
        account = state
        self.identity = state == .available ? identity : nil
        if log.accountChecked(previous: previous, current: state, identity: self.identity) {
            logger.info("Sync log matched to the iCloud account (a different one starts it over)")
            save()
        }
    }

    private func record(_ event: SyncEvent) {
        guard log.record(event) else { return }
        save()
    }

    private func save() {
        if let defaults { log.save(to: defaults) }
    }

    /// The app's container, made once. A Mac build without the iCloud
    /// entitlement (unsigned) gets none: CloudKit would raise an exception.
    private func cloudKitContainer() -> CKContainer? {
        if let container { return container }
        #if os(macOS)
        guard Self.hasCloudKitEntitlement else { return nil }
        #endif
        let made = CKContainer(identifier: ScribeIDs.cloudKitContainer)
        container = made
        return made
    }

    #if os(macOS)
    private static let hasCloudKitEntitlement: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) != nil
    }()
    #endif
}

extension SyncEventKind {
    init?(_ type: NSPersistentCloudKitContainer.EventType) {
        switch type {
        case .setup: self = .setup
        case .import: self = .import
        case .export: self = .export
        @unknown default: return nil
        }
    }
}

extension CloudAccountState {
    init(_ status: CKAccountStatus) {
        self = switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .unknown
        @unknown default: .unknown
        }
    }
}
