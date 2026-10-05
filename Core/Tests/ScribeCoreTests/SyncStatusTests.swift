import Foundation
import Testing
@testable import ScribeCore

struct SyncLogTests {
    let monday = TestCalendar.monday

    func at(_ minutes: Double) -> Date { monday.addingTimeInterval(minutes * 60) }

    func event(_ kind: SyncEventKind, _ minutes: Double, _ failure: SyncFailureReason? = nil) -> SyncEvent {
        SyncEvent(kind: kind, endDate: at(minutes), failure: failure)
    }

    @Test func importsAndExportsCountAsSyncsSetupDoesNot() {
        var log = SyncLog()
        log.record(event(.setup, 0))
        #expect(log.lastSuccess == nil)
        log.record(event(.import, 1))
        #expect(log.lastSuccess == at(1))
        log.record(event(.export, 2))
        #expect(log.lastSuccess == at(2))
    }

    @Test func lastSuccessNeverMovesBack() {
        var log = SyncLog()
        log.record(event(.export, 5))
        #expect(log.record(event(.import, 3)) == false)
        #expect(log.lastSuccess == at(5))
    }

    @Test func aFailureStandsUntilItsKindSucceeds() {
        var log = SyncLog()
        log.record(event(.export, 1))
        log.record(event(.export, 2, .offline))
        #expect(log.latestFailure == SyncFailure(kind: .export, date: at(2), reason: .offline))
        #expect(log.lastSuccess == at(1), "a failure doesn't move Last synced")

        log.record(event(.import, 3))
        #expect(log.latestFailure?.kind == .export, "an import doesn't prove uploads work again")
        #expect(log.lastSuccess == at(3))

        log.record(event(.export, 4))
        #expect(log.latestFailure == nil)
    }

    @Test func aNewerFailureOfTheSameKindReplacesTheOlder() {
        var log = SyncLog()
        log.record(event(.import, 1, .offline))
        log.record(event(.import, 2, .iCloudBusy))
        #expect(log.failures == [SyncFailure(kind: .import, date: at(2), reason: .iCloudBusy)])
    }

    @Test func latestFailureIsTheNewest() {
        var log = SyncLog()
        log.record(event(.export, 5, .storageFull))
        log.record(event(.import, 3, .offline))
        #expect(log.latestFailure?.reason == .storageFull)
    }

    @Test func aSyncClearsASetupFailure() {
        var log = SyncLog()
        log.record(event(.setup, 0, .notSignedIn))
        #expect(log.latestFailure?.kind == .setup)
        log.record(event(.import, 1))
        #expect(log.latestFailure == nil, "an import can only run once setup worked")

        log.record(event(.setup, 2, .notSignedIn))
        log.record(event(.setup, 3))
        #expect(log.latestFailure == nil)
    }

    @Test func aSuccessDoesNotClearALaterFailure() {
        var log = SyncLog()
        log.record(event(.export, 5, .offline))
        log.record(event(.export, 4))
        #expect(log.latestFailure?.date == at(5))
    }

    @Test func roundTripsThroughDefaults() {
        let name = "scribe-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(SyncLog(from: defaults) == SyncLog(), "nothing saved yet")

        var log = SyncLog()
        log.record(event(.import, 1))
        log.record(event(.export, 2, .other("CKErrorDomain 15")))
        log.save(to: defaults)
        #expect(SyncLog(from: defaults) == log)

        defaults.set(Data("not json".utf8), forKey: SyncLog.defaultsKey)
        #expect(SyncLog(from: defaults) == SyncLog(), "unreadable data starts over")
    }
}

struct SyncEventTests {
    let date = TestCalendar.monday

    func ckError(_ code: Int, _ info: [String: Any] = [:]) -> NSError {
        NSError(domain: "CKErrorDomain", code: code, userInfo: info)
    }

    func reason(_ error: NSError) -> SyncFailureReason? {
        SyncEvent(kind: .export, endDate: date, succeeded: false, error: error)?.failure
    }

    @Test func aSuccessHasNoFailure() {
        let event = SyncEvent(kind: .import, endDate: date, succeeded: true, error: nil)
        #expect(event == SyncEvent(kind: .import, endDate: date, failure: nil))
    }

    @Test func aCancelledOperationIsIgnored() {
        #expect(SyncEvent(kind: .export, endDate: date, succeeded: false, error: ckError(20)) == nil)
    }

    @Test func aFailureWithoutAnErrorStillCounts() {
        #expect(SyncEvent(kind: .export, endDate: date, succeeded: false, error: nil)?.failure == .other("no error"))
    }

    nonisolated static let cloudKitCodes: [(Int, SyncFailureReason)] = [
        (3, .offline), (4, .offline),
        (6, .iCloudBusy), (7, .iCloudBusy), (23, .iCloudBusy), (34, .iCloudBusy),
        (9, .notSignedIn),
        (25, .storageFull),
        (36, .accountNeedsAttention), (32, .accountNeedsAttention),
        (15, .other("CKErrorDomain 15")),
    ]

    @Test(arguments: cloudKitCodes)
    func cloudKitCodesBecomeReasons(code: Int, expected: SyncFailureReason) {
        #expect(reason(ckError(code)) == expected)
    }

    @Test func noNetworkIsOffline() {
        #expect(reason(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)) == .offline)
    }

    @Test func coreDataWithoutAnAccountIsNotSignedIn() {
        #expect(reason(NSError(domain: NSCocoaErrorDomain, code: 134400)) == .notSignedIn)
    }

    @Test func partialFailureUsesItsMostTellingInnerError() {
        let inner: [String: NSError] = ["a": ckError(15), "b": ckError(25), "c": ckError(3)]
        #expect(reason(ckError(2, ["CKPartialErrors": inner])) == .storageFull)
        #expect(reason(ckError(2)) == .other("CKErrorDomain 2"))
    }

    @Test func anUnderlyingErrorIsConsulted() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134419, userInfo: [NSUnderlyingErrorKey: ckError(4)])
        #expect(reason(wrapped) == .offline)
        let opaque = NSError(domain: NSCocoaErrorDomain, code: 134419, userInfo: [NSUnderlyingErrorKey: ckError(15)])
        #expect(reason(opaque) == .other("NSCocoaErrorDomain 134419"), "the outer error names it when the inner one says nothing more")
    }
}
