import Foundation
import Testing
@testable import ScribeCore

/// The status lines of Settings › Claude.
struct MailboxStatusTests {
    let now = TestCalendar.monday // Mon 2026-10-05 10:00 Jerusalem
    let labels = DueLabels(calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"))

    func text(_ status: MailboxStatus, syncing: Bool = false) -> MailboxStatusText {
        MailboxStatusText(status: status, isSyncing: syncing, now: now, labels: labels)
    }

    @Test func neverSynced() {
        let text = text(MailboxStatus())
        #expect(text.line == "Not synced yet")
        #expect(text.problem == nil)
    }

    @Test func lastSyncedReadsLikeICloudsLine() {
        var status = MailboxStatus()
        status.succeeded(at: now.addingTimeInterval(-20))
        #expect(text(status).line == "Last synced just now")
        status.succeeded(at: TestCalendar.date(2026, 10, 5, 9, 14))
        #expect(text(status).line == "Last synced just now", "never moves backwards")

        var older = MailboxStatus()
        older.succeeded(at: TestCalendar.date(2026, 10, 5, 9, 14))
        #expect(text(older).line == "Last synced at 09:14")
        var yesterday = MailboxStatus()
        yesterday.succeeded(at: TestCalendar.date(2026, 10, 4, 22, 10))
        #expect(text(yesterday).line == "Last synced yesterday at 22:10")
    }

    @Test func syncingWins() {
        var status = MailboxStatus()
        status.succeeded(at: now)
        #expect(text(status, syncing: true).line == "Syncing…")
    }

    @Test func aFailureIsExplainedUntilASuccess() {
        var status = MailboxStatus()
        status.succeeded(at: TestCalendar.date(2026, 10, 5, 9, 14))
        status.failed(.offline)
        let offline = text(status)
        #expect(offline.line == "Last synced at 09:14")
        #expect(offline.problem?.hasPrefix("Couldn’t reach the mailbox") == true)
        status.succeeded(at: now)
        #expect(text(status).problem == nil)
    }

    @Test(arguments: [
        (MailboxFailure.linkRejected, "The mailbox didn’t accept this link."),
        (.server(500), "The mailbox answered with an error (500)."),
        (.server(0), "Something went wrong talking to the mailbox."),
        (.unreadable, "Scribe couldn’t read the mailbox’s answer."),
    ])
    func eachFailureHasItsSentence(failure: MailboxFailure, prefix: String) {
        var status = MailboxStatus()
        status.failed(failure)
        #expect(text(status).problem?.hasPrefix(prefix) == true)
    }

    @Test func isSavedAndRead() throws {
        let defaults = try #require(UserDefaults(suiteName: "MailboxStatusTests-\(UUID())"))
        var status = MailboxStatus()
        status.succeeded(at: now)
        status.failed(.server(503))
        status.save(to: defaults)
        #expect(MailboxStatus(from: defaults) == status)
    }
}
