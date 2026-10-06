import Foundation
import Observation
import ScribeCore
import os
#if os(iOS)
import UIKit
#else
import AppKit
#endif

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "mailbox")

/// The Claude mailbox (`mailbox/` Worker) over HTTP.
protocol MailboxTransport: Sendable {
    func inbox(_ connection: MailboxConnection) async throws -> [MailboxItem]
    func acknowledge(_ ids: [String], _ connection: MailboxConnection) async throws
    func publish(_ snapshot: MailboxSnapshot, _ connection: MailboxConnection) async throws
}

struct URLSessionMailboxTransport: MailboxTransport {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = MailboxRequests.timeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func inbox(_ connection: MailboxConnection) async throws -> [MailboxItem] {
        try MailboxRequests.decodeInbox(try await send(MailboxRequests.inbox(connection)))
    }

    func acknowledge(_ ids: [String], _ connection: MailboxConnection) async throws {
        _ = try await send(MailboxRequests.acknowledge(ids, to: connection))
    }

    func publish(_ snapshot: MailboxSnapshot, _ connection: MailboxConnection) async throws {
        _ = try await send(MailboxRequests.publish(snapshot, to: connection))
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try MailboxRequests.check(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        return data
    }
}

/// Keeps Scribe and the Claude mailbox in step: collects the items Claude
/// queued (adding them to the store, which iCloud syncs) and publishes the
/// categories and what's coming up. Runs on launch, when the app comes to
/// the front, in background refresh (iOS) and from Settings; a store change
/// publishes again after a short pause. Failures never interrupt anything:
/// they show in Settings › Claude.
@MainActor
@Observable
final class MailboxSync {
    static let shared = MailboxSync()

    /// Nil until the user pastes a connector link.
    private(set) var connection: MailboxConnection?
    private(set) var status: MailboxStatus
    private(set) var isSyncing = false

    /// Automatic syncs (launch, activation) at most this often.
    private static let automaticInterval: TimeInterval = 15
    /// A store change publishes once changes settle.
    private static let publishDelay: Duration = .seconds(3)
    /// An unchanged snapshot is published again only after this long, to keep its age honest.
    private static let republishInterval: TimeInterval = 5 * 60

    @ObservationIgnored private let links: any MailboxLinkStore
    @ObservationIgnored private let transport: any MailboxTransport
    /// Per device: the status in the standard defaults, the ledger in the App
    /// Group's. Nil in UI-test runs (nothing is saved).
    @ObservationIgnored private let statusDefaults: UserDefaults?
    @ObservationIgnored private let ledgerDefaults: UserDefaults?
    @ObservationIgnored private var ledger = MailboxLedger()
    @ObservationIgnored private var store: (any ItemStore)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var pendingPublish: Task<Void, Never>?
    @ObservationIgnored private var lastAutomaticSync: Date?
    @ObservationIgnored private var lastPublished: (snapshot: MailboxSnapshot, connection: MailboxConnection)?

    private init() {
        if SharedStore.isUITesting {
            links = MemoryMailboxLinkStore()
            #if DEBUG
            transport = MailboxDemo.transport ?? URLSessionMailboxTransport()
            #else
            transport = URLSessionMailboxTransport()
            #endif
            statusDefaults = nil
            ledgerDefaults = nil
        } else {
            links = KeychainMailboxLinkStore()
            transport = URLSessionMailboxTransport()
            statusDefaults = .standard
            ledgerDefaults = UserDefaults(suiteName: ScribeIDs.appGroup)
        }
        status = statusDefaults.map { MailboxStatus(from: $0) } ?? MailboxStatus()
        if let ledgerDefaults { ledger = MailboxLedger(from: ledgerDefaults) }
        connection = (try? links.load()).flatMap(MailboxConnection.init(link:))
    }

    /// Called once when the app's store opens (`AppProcess`).
    func start(store: any ItemStore) {
        guard self.store == nil else { return }
        self.store = store
        watchStore()
        #if os(iOS)
        let didBecomeActive = UIApplication.didBecomeActiveNotification
        #else
        let didBecomeActive = NSApplication.didBecomeActiveNotification
        #endif
        observers.append(NotificationCenter.default.addObserver(forName: didBecomeActive, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MailboxSync.shared.syncAutomatically() }
        })
        syncAutomatically()
    }

    // MARK: Settings

    /// Saves the link (shared with the user's other devices) and syncs.
    /// False when it isn't a mailbox link.
    @discardableResult
    func connect(link: String) -> Bool {
        guard let connection = MailboxConnection(link: link) else { return false }
        do {
            try links.save(connection.link)
        } catch {
            log.error("Couldn't save the connector link; using it until Scribe quits")
        }
        setConnection(connection)
        Task { await syncNow() }
        return true
    }

    /// Forgets the link here and, through iCloud Keychain, on the other devices.
    func disconnect() {
        links.delete()
        setConnection(nil)
    }

    // MARK: Syncing

    /// Collects, then publishes. A call while a sync runs waits for it and
    /// one more pass.
    func syncNow() async {
        if let running {
            needsAnotherPass = true
            await running.value
            return
        }
        let task = Task { await runPasses() }
        running = task
        await task.value
    }

    /// Launch and activation: re-reads the link (the other device may have
    /// changed it), at most every few seconds.
    private func syncAutomatically() {
        reloadLink()
        let now = Date()
        if let last = lastAutomaticSync, now.timeIntervalSince(last) < Self.automaticInterval { return }
        lastAutomaticSync = now
        Task { await syncNow() }
    }

    private func runPasses() async {
        repeat {
            needsAnotherPass = false
            await pass()
        } while needsAnotherPass
        running = nil
    }

    private func pass() async {
        guard let connection, let store else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let items = try await transport.inbox(connection)
            if !items.isEmpty {
                let outcome = MailboxIntake.collect(items, into: store, ledger: &ledger)
                if let ledgerDefaults { ledger.save(to: ledgerDefaults) }
                log.info("Collected \(outcome.added.count) of \(items.count) items from Claude (\(outcome.failed.count) failed)")
                if !outcome.acknowledged.isEmpty {
                    try await transport.acknowledge(outcome.acknowledged, connection)
                }
                if !outcome.added.isEmpty { await StoreChanged.notify() }
            }
            try await publish(store, to: connection, force: true)
            record(nil, for: connection)
        } catch {
            record(MailboxFailure(error), for: connection)
        }
    }

    /// `force`: publish even when nothing changed (it refreshes the snapshot's age).
    private func publish(_ store: any ItemStore, to connection: MailboxConnection, force: Bool) async throws {
        let snapshot = MailboxSnapshotBuilder.build(categories: store.categories, items: store.datedOpenItems(), now: Date(), calendar: .autoupdatingCurrent)
        if !force, let last = lastPublished, last.connection == connection, last.snapshot.hasSameContent(as: snapshot),
           snapshot.updatedAt.timeIntervalSince(last.snapshot.updatedAt) < Self.republishInterval {
            return
        }
        try await transport.publish(snapshot, connection)
        lastPublished = (snapshot, connection)
    }

    /// Publishes a moment after the store changes (edits here, iCloud
    /// imports, items collected). Reading the store registers the
    /// observation; any later change fires it once.
    private func watchStore() {
        guard let store else { return }
        withObservationTracking {
            _ = store.categories
        } onChange: {
            Task { @MainActor in
                MailboxSync.shared.watchStore()
                MailboxSync.shared.publishSoon()
            }
        }
    }

    private func publishSoon() {
        guard connection != nil else { return }
        pendingPublish?.cancel()
        pendingPublish = Task {
            try? await Task.sleep(for: Self.publishDelay)
            guard !Task.isCancelled, running == nil, let store, let connection else { return }
            do {
                try await publish(store, to: connection, force: false)
                record(nil, for: connection)
            } catch {
                record(MailboxFailure(error), for: connection)
            }
        }
    }

    private func record(_ failure: MailboxFailure?, for used: MailboxConnection) {
        guard used == connection else { return } // disconnected or changed meanwhile
        if let failure {
            log.error("Mailbox sync failed: \(String(describing: failure), privacy: .public)")
            status.failed(failure)
        } else {
            status.succeeded(at: Date())
        }
        if let statusDefaults { status.save(to: statusDefaults) }
    }

    /// A Keychain that can't be read right now changes nothing.
    private func reloadLink() {
        let link: String?
        do {
            link = try links.load()
        } catch {
            return
        }
        let stored = link.flatMap(MailboxConnection.init(link:))
        if stored != connection { setConnection(stored) }
    }

    private func setConnection(_ new: MailboxConnection?) {
        guard new != connection else { return }
        connection = new
        lastPublished = nil
        pendingPublish?.cancel()
        // The status describes one mailbox.
        status = MailboxStatus()
        if let statusDefaults { status.save(to: statusDefaults) }
    }
}
