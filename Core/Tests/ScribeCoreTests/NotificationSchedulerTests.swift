import Foundation
import Testing
@testable import ScribeCore

/// A notification center in memory. `holdsPrompt` keeps the permission
/// prompt open until `answerPrompt(_:)`, like a user who hasn't tapped yet.
@MainActor
final class FakeNotificationCenter: NotificationCenterClient {
    var status: NotificationPermission
    var promptAnswer: NotificationPermission = .allowed
    var holdsPrompt = false
    /// Makes the prompt fail and leaves the status undetermined, as on an
    /// unsigned Mac build (`UNErrorCodeNotificationsNotAllowed`).
    var promptError: (any Error)?
    private(set) var prompts = 0
    private(set) var pendingRequests: [String: PlannedNotification] = [:]
    var delivered: [String] = []
    private var openPrompt: CheckedContinuation<Void, Never>?

    init(status: NotificationPermission = .allowed) {
        self.status = status
    }

    var pendingIDs: Set<String> { Set(pendingRequests.keys) }

    func authorization() async -> NotificationPermission { status }

    func requestAuthorization() async throws -> NotificationPermission {
        prompts += 1
        if let promptError { throw promptError }
        if holdsPrompt {
            await withCheckedContinuation { openPrompt = $0 }
        }
        status = promptAnswer
        return status
    }

    func answerPrompt(_ answer: NotificationPermission) {
        promptAnswer = answer
        openPrompt?.resume()
        openPrompt = nil
    }

    func pending() async -> [NotificationDiff.Pending] {
        pendingRequests.values.map { .init(id: $0.id, fingerprint: $0.fingerprint) }
    }

    func add(_ request: PlannedNotification) async throws {
        pendingRequests[request.id] = request
    }

    func removePending(_ identifiers: [String]) {
        for id in identifiers { pendingRequests[id] = nil }
    }

    func deliveredIdentifiers() async -> [String] { delivered }

    func removeDelivered(_ identifiers: [String]) {
        delivered.removeAll { identifiers.contains($0) }
    }
}

@MainActor
struct NotificationSchedulerTests {
    let clock = TestClock() // Mon 2026-10-05 10:00 Jerusalem
    let tomorrowNine = DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60)

    func freshDefaults() -> UserDefaults {
        let name = "scribe-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    final class Opener {
        var store: (any ItemStore)?
        var calls = 0
        init(_ store: (any ItemStore)?) { self.store = store }
    }

    final class Events {
        var list: [NotificationScheduler.Event] = []
    }

    func makeScheduler(
        center: FakeNotificationCenter,
        opener: Opener,
        events: Events = Events(),
        defaults: UserDefaults? = nil,
        mayAsk: Bool = true
    ) -> NotificationScheduler {
        let scheduler = NotificationScheduler(
            center: center,
            defaults: defaults ?? freshDefaults(),
            fallbackSettings: .iOSDefault,
            planner: NotificationPlanner(calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB")),
            now: { [clock] in clock.now },
            coalescing: .zero,
            openStore: {
                opener.calls += 1
                return opener.store
            },
            mayAskForPermission: { mayAsk }
        )
        scheduler.onEvent = { events.list.append($0) }
        return scheduler
    }

    /// Waits (up to 2 s) for work started by an observation callback.
    func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    // MARK: rescheduleNow

    /// A background launch (refresh task, intent run in the app) has no
    /// window, so nothing opened the store: `rescheduleNow` opens it itself.
    @Test func rescheduleNowOpensTheStoreFirst() async throws {
        let store = try makeStore(clock: clock)
        let id = try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter()
        let opener = Opener(store)
        let scheduler = makeScheduler(center: center, opener: opener)

        await scheduler.rescheduleNow()
        #expect(opener.calls == 1)
        #expect(center.pendingIDs == [PlannedNotification.identifier(forItem: id), "summary.2026-10-06"])

        await scheduler.rescheduleNow()
        #expect(opener.calls == 1, "one store per process: opened once, then kept")
    }

    @Test func rescheduleNowWithoutAStoreReportsIt() async {
        let center = FakeNotificationCenter()
        let events = Events()
        let scheduler = makeScheduler(center: center, opener: Opener(nil), events: events)
        await scheduler.rescheduleNow()
        #expect(events.list == [.storeUnavailable])
        #expect(center.pendingIDs.isEmpty)
    }

    @Test func attachedStoreIsUsedWithoutOpening() async throws {
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter()
        let opener = Opener(nil)
        let scheduler = makeScheduler(center: center, opener: opener)
        scheduler.attach(store)
        await scheduler.rescheduleNow()
        #expect(opener.calls == 0)
        #expect(center.pendingIDs.count == 2)
    }

    // MARK: Keeping up with the store

    @Test func storeWritesReplanOnTheirOwn() async throws {
        let store = try makeStore(clock: clock)
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, opener: Opener(store))
        await scheduler.rescheduleNow()
        #expect(center.pendingIDs.isEmpty)

        let id = try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        try await eventually { center.pendingIDs.contains(PlannedNotification.identifier(forItem: id)) }

        try store.setDone(id, true)
        try await eventually { center.pendingIDs.isEmpty }
    }

    /// A CloudKit import or a widget write changes the file behind the app's
    /// store; `SyncRefresher` then calls `refresh()`, which re-plans.
    @Test func refreshAfterAnOutsideWriteReplans() async throws {
        let container = try StoreFactory.inMemory()
        let app = SwiftDataItemStore(container: container, calendar: TestCalendar.jerusalem, now: { [clock] in clock.now })
        let elsewhere = SwiftDataItemStore(container: container, calendar: TestCalendar.jerusalem, now: { [clock] in clock.now })
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, opener: Opener(app))
        await scheduler.rescheduleNow()

        try elsewhere.addItem(ItemDraft(title: "arrived by sync", due: tomorrowNine))
        try await Task.sleep(for: .milliseconds(50))
        #expect(center.pendingIDs.isEmpty, "the app's store hasn't noticed yet")

        app.refresh()
        try await eventually { center.pendingIDs.count == 2 }
    }

    // MARK: Permission

    /// A prompt the user hasn't answered must not hold up passes or
    /// `rescheduleNow` callers (a background task waiting to finish).
    @Test func anOpenPromptDoesNotBlockRescheduling() async throws {
        let store = try makeStore(clock: clock)
        let id = try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter(status: .notDetermined)
        center.holdsPrompt = true
        let scheduler = makeScheduler(center: center, opener: Opener(store))

        await scheduler.rescheduleNow() // returns although the prompt is open
        try await eventually { center.prompts == 1 }
        #expect(scheduler.permission == .notDetermined)
        #expect(center.pendingIDs.isEmpty)
        await scheduler.rescheduleNow()
        #expect(center.prompts == 1, "one prompt at a time")

        center.answerPrompt(.allowed)
        await scheduler.waitUntilIdle()
        #expect(scheduler.permission == .allowed)
        #expect(center.pendingIDs.contains(PlannedNotification.identifier(forItem: id)))
    }

    struct PromptFailed: Error {}

    func passes(_ events: Events) -> Int {
        events.list.filter { if case .rescheduled = $0 { true } else { false } }.count
    }

    /// A prompt that fails and leaves permission undetermined must not be
    /// retried by the passes that follow — that would loop.
    @Test func aFailedPromptIsNotRetriedAutomatically() async throws {
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter(status: .notDetermined)
        center.promptError = PromptFailed()
        let events = Events()
        let scheduler = makeScheduler(center: center, opener: Opener(store), events: events)

        await scheduler.rescheduleNow()
        await scheduler.waitUntilIdle()
        for _ in 0..<3 {
            scheduler.setNeedsReschedule()
            await scheduler.rescheduleNow()
        }
        try store.addItem(ItemDraft(title: "Another", due: tomorrowNine))
        try await Task.sleep(for: .milliseconds(100))
        await scheduler.waitUntilIdle()

        #expect(center.prompts == 1)
        #expect(events.list.filter { if case .permissionRequestFailed = $0 { true } else { false } }.count == 1)
        #expect(scheduler.permission == .notDetermined)
        #expect(center.pendingIDs.isEmpty)
        #expect(passes(events) <= 6, "no re-plan loop: \(passes(events)) passes")
    }

    /// The Settings button asks again, once per tap, and a failure there
    /// doesn't start a re-plan.
    @Test func explicitRequestRetriesExactlyOnce() async throws {
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter(status: .notDetermined)
        center.promptError = PromptFailed()
        let events = Events()
        let scheduler = makeScheduler(center: center, opener: Opener(store), events: events)
        await scheduler.rescheduleNow()
        await scheduler.waitUntilIdle()
        #expect(center.prompts == 1)
        let passesBefore = passes(events)

        await scheduler.requestPermission()
        try await Task.sleep(for: .milliseconds(50))
        await scheduler.waitUntilIdle()
        #expect(center.prompts == 2)
        #expect(passes(events) == passesBefore)

        center.promptError = nil
        await scheduler.requestPermission()
        await scheduler.waitUntilIdle()
        #expect(center.prompts == 3)
        #expect(scheduler.permission == .allowed)
        #expect(center.pendingIDs.count == 2, "answered: re-planned")
    }

    @Test func noPromptWithNothingToNotify() async throws {
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "undated"))
        let center = FakeNotificationCenter(status: .notDetermined)
        let scheduler = makeScheduler(center: center, opener: Opener(store))
        await scheduler.rescheduleNow()
        #expect(center.prompts == 0)
    }

    @Test func noPromptWhileInTheBackground() async throws {
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter(status: .notDetermined)
        let scheduler = makeScheduler(center: center, opener: Opener(store), mayAsk: false)
        await scheduler.rescheduleNow()
        #expect(center.prompts == 0)
        #expect(center.pendingIDs.isEmpty)
    }

    @Test func requestPermissionAsksAndReplans() async throws {
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter(status: .notDetermined)
        let scheduler = makeScheduler(center: center, opener: Opener(store), mayAsk: false)
        await scheduler.rescheduleNow()
        await scheduler.requestPermission()
        await scheduler.waitUntilIdle()
        #expect(center.prompts == 1)
        #expect(scheduler.permission == .allowed)
        #expect(center.pendingIDs.count == 2)
    }

    @Test func deniedPermissionClearsOurPendingRequests() async throws {
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, opener: Opener(store))
        await scheduler.rescheduleNow()
        #expect(center.pendingIDs.count == 2)
        center.status = .denied
        await scheduler.rescheduleNow()
        #expect(scheduler.permission == .denied)
        #expect(center.pendingIDs.isEmpty)
    }

    // MARK: Settings

    @Test func settingsAreReadSavedAndReplanned() async throws {
        let defaults = freshDefaults()
        NotificationSettings(isEnabled: true, morningSummaryEnabled: false, morningSummaryMinute: 450).save(to: defaults)
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, opener: Opener(store), defaults: defaults)
        #expect(scheduler.settings.morningSummaryMinute == 450)
        await scheduler.rescheduleNow()
        #expect(center.pendingIDs.count == 1, "summary off")

        scheduler.settings.isEnabled = false
        await scheduler.waitUntilIdle()
        #expect(center.pendingIDs.isEmpty)
        #expect(NotificationSettings(from: defaults).isEnabled == false)
    }

    /// Settings' time picker and summary switch (Phase 6) re-plan at once.
    @Test func summaryTimeAndSwitchReplan() async throws {
        let store = try makeStore(clock: clock)
        try store.addItem(ItemDraft(title: "Call Dan", due: DueDate(day: LocalDay(2026, 10, 6))))
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, opener: Opener(store))
        await scheduler.rescheduleNow()
        #expect(center.pendingRequests["summary.2026-10-06"]?.trigger.hour == 9)

        scheduler.settings.setSummaryTime(TestCalendar.date(2026, 10, 5, 7, 30), calendar: TestCalendar.jerusalem)
        await scheduler.waitUntilIdle()
        let moved = center.pendingRequests["summary.2026-10-06"]?.trigger
        #expect(moved?.hour == 7)
        #expect(moved?.minute == 30)

        scheduler.settings.morningSummaryEnabled = false
        await scheduler.waitUntilIdle()
        #expect(center.pendingIDs.isEmpty)
    }

    // MARK: Actions

    /// A button tapped while Scribe wasn't running: the store opens, the
    /// item changes, and the alerts match before the handler returns.
    @Test func actionOpensTheStoreAppliesAndReplans() async throws {
        let store = try makeStore(clock: clock)
        let id = try store.addItem(ItemDraft(title: "Call Dan", due: DueDate(day: LocalDay(2026, 10, 5), minute: 9 * 60)))
        let center = FakeNotificationCenter()
        let opener = Opener(store)
        let scheduler = makeScheduler(center: center, opener: opener)
        let alert = PlannedNotification.identifier(forItem: id)

        await scheduler.perform(.inAnHour, itemID: id)
        #expect(opener.calls == 1)
        #expect(store.item(id)?.due == DueDate(day: LocalDay(2026, 10, 5), minute: 11 * 60))
        #expect(center.pendingRequests[alert]?.fireDate == TestCalendar.date(2026, 10, 5, 11, 0))

        await scheduler.perform(.done, itemID: id)
        #expect(opener.calls == 1)
        #expect(store.item(id)?.isDone == true)
        #expect(center.pendingRequests[alert] == nil)
    }

    @Test func actionIsReportedWhenTheStoreWontOpen() async {
        let center = FakeNotificationCenter()
        let events = Events()
        let scheduler = makeScheduler(center: center, opener: Opener(nil), events: events)
        let id = UUID()
        await scheduler.perform(.done, itemID: id)
        #expect(events.list == [.actionDropped(.done, itemID: id)])
    }

    // MARK: Delivered alerts

    @Test func deliveredAlertsOfClosedItemsAreRemoved() async throws {
        let store = try makeStore(clock: clock)
        let open = try store.addItem(ItemDraft(title: "open", due: DueDate(day: LocalDay(2026, 10, 5), minute: 9 * 60)))
        let done = try store.addItem(ItemDraft(title: "done", due: DueDate(day: LocalDay(2026, 10, 5), minute: 9 * 60)))
        try store.setDone(done, true)
        let center = FakeNotificationCenter()
        let kept = [PlannedNotification.identifier(forItem: open), "summary.2026-10-05", "foreign"]
        center.delivered = kept + [PlannedNotification.identifier(forItem: done), PlannedNotification.identifier(forItem: UUID())]
        let scheduler = makeScheduler(center: center, opener: Opener(store))
        await scheduler.rescheduleNow()
        #expect(center.delivered == kept)
    }

    @Test func eachPassIsReported() async throws {
        let store = try makeStore(clock: clock)
        let id = try store.addItem(ItemDraft(title: "Call Dan", due: tomorrowNine))
        let events = Events()
        let scheduler = makeScheduler(center: FakeNotificationCenter(), opener: Opener(store), events: events)
        await scheduler.rescheduleNow()
        await scheduler.rescheduleNow()
        let ids = ["summary.2026-10-06", PlannedNotification.identifier(forItem: id)]
        #expect(events.list == [
            .rescheduled(planned: ids, added: 2, removed: 0, permission: .allowed),
            .rescheduled(planned: ids, added: 0, removed: 0, permission: .allowed),
        ])
    }
}
