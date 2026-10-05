import Foundation
import Testing
@testable import ScribeCore

struct SyncStatusTextTests {
    let labels = DueLabels(calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"))
    let now = TestCalendar.monday // Mon 5 Oct 2026, 10:00

    func text(_ account: CloudAccountState, _ log: SyncLog = SyncLog(), device: DeviceKind = .iPhone, now: Date? = nil) -> SyncStatusText {
        SyncStatusText(account: account, log: log, now: now ?? self.now, device: device, labels: labels)
    }

    func log(syncedAt date: Date? = nil, failing failure: SyncEvent? = nil) -> SyncLog {
        var log = SyncLog()
        if let date { log.record(SyncEvent(kind: .import, endDate: date, failure: nil)) }
        if let failure { log.record(failure) }
        return log
    }

    @Test func notSignedInSaysSoAndHowToFixIt() {
        let iPhone = text(.noAccount)
        #expect(iPhone.headline == "Sync off — sign in to iCloud") // spec §13
        #expect(iPhone.symbol == .off)
        #expect(iPhone.detail == "Open Settings, sign in with your Apple Account and make sure iCloud is on for Scribe. Until then everything stays on this iPhone; nothing is lost.")
        #expect(iPhone.lastSynced == nil)

        let mac = text(.noAccount, device: .mac)
        #expect(mac.detail == "Open System Settings, sign in with your Apple Account and make sure iCloud is on for Scribe. Until then everything stays on this Mac; nothing is lost.")
    }

    @Test func signedInShowsWhenItLastSynced() {
        let status = text(.available, log(syncedAt: TestCalendar.date(2026, 10, 5, 9, 14)))
        #expect(status.headline == "Syncing with iCloud")
        #expect(status.symbol == .on)
        #expect(status.detail == nil)
        #expect(status.lastSynced == "Last synced at 09:14")
        #expect(status.problem == nil)
    }

    nonisolated static let ages: [(Date, String)] = [
        (TestCalendar.monday.addingTimeInterval(-59), "Last synced just now"),
        (TestCalendar.monday.addingTimeInterval(30), "Last synced just now"), // a clock that ran ahead
        (TestCalendar.date(2026, 10, 5, 0, 5), "Last synced at 00:05"),
        (TestCalendar.date(2026, 10, 4, 22, 10), "Last synced yesterday at 22:10"),
        (TestCalendar.date(2026, 10, 2, 9, 5), "Last synced Fri 2 Oct at 09:05"),
        (TestCalendar.date(2025, 12, 31, 23, 59), "Last synced Wed, 31 Dec 2025 at 23:59"),
    ]

    @Test(arguments: ages)
    func lastSyncedReadsNaturally(syncedAt: Date, expected: String) {
        #expect(text(.available, log(syncedAt: syncedAt)).lastSynced == expected)
    }

    @Test func signedInButNeverSynced() {
        #expect(text(.available).lastSynced == "Not synced yet on this iPhone")
        #expect(text(.available, device: .mac).lastSynced == "Not synced yet on this Mac")
    }

    @Test func aPastSyncStaysVisibleAfterSigningOut() {
        let status = text(.noAccount, log(syncedAt: TestCalendar.date(2026, 10, 4, 22, 10)))
        #expect(status.lastSynced == "Last synced yesterday at 22:10")
    }

    @Test func otherAccountStates() {
        #expect(text(.checking).headline == "Checking iCloud…")
        #expect(text(.checking).symbol == .checking)
        #expect(text(.restricted).headline == "iCloud is restricted on this iPhone")
        #expect(text(.restricted).symbol == .off)
        #expect(text(.temporarilyUnavailable).headline == "iCloud needs attention")
        #expect(text(.temporarilyUnavailable).symbol == .warning)
        #expect(text(.unknown).headline == "Couldn’t check iCloud")
        for state in [CloudAccountState.restricted, .temporarilyUnavailable, .unknown] {
            #expect(text(state).detail?.isEmpty == false)
        }
    }

    @Test func aFailureShowsWhileSignedIn() {
        let offline = SyncEvent(kind: .export, endDate: now, failure: .offline)
        let status = text(.available, log(syncedAt: TestCalendar.date(2026, 10, 5, 9, 14), failing: offline))
        #expect(status.problem == "Offline — changes are saved on this iPhone and upload once it’s back online.")
        #expect(status.symbol == .warning)
        #expect(status.lastSynced == "Last synced at 09:14")
    }

    @Test func theAccountRowExplainsInsteadOfTheError() {
        let failure = SyncEvent(kind: .setup, endDate: now, failure: .notSignedIn)
        #expect(text(.noAccount, log(failing: failure)).problem == nil)
        #expect(text(.restricted, log(failing: failure)).problem == nil)
        #expect(text(.temporarilyUnavailable, log(failing: failure)).problem == nil)
        #expect(text(.unknown, log(failing: failure)).problem != nil)
    }

    nonisolated static let problems: [(SyncFailureReason, SyncEventKind, String)] = [
        (.iCloudBusy, .import, "iCloud is busy — Scribe will try again shortly."),
        (.notSignedIn, .setup, "iCloud didn’t accept the sign-in. Check your Apple Account in Settings."),
        (.storageFull, .export, "Your iCloud storage is full — changes stay on this iPhone until there’s room."),
        (.accountNeedsAttention, .export, "iCloud needs attention — check your Apple Account in Settings."),
        (.other("CKErrorDomain 15"), .export, "The last upload to iCloud failed (CKErrorDomain 15). Scribe will try again."),
        (.other("CKErrorDomain 15"), .import, "The last download from iCloud failed (CKErrorDomain 15). Scribe will try again."),
        (.other("NSCocoaErrorDomain 134060"), .setup, "iCloud sync couldn’t start (NSCocoaErrorDomain 134060). Scribe will try again."),
    ]

    @Test(arguments: problems)
    func problemSentences(reason: SyncFailureReason, kind: SyncEventKind, expected: String) {
        let failure = SyncEvent(kind: kind, endDate: now, failure: reason)
        #expect(text(.available, log(failing: failure)).problem == expected)
    }
}

struct NotificationSectionTextTests {
    func section(_ enabled: Bool = true, summary: Bool = true, _ permission: NotificationPermission = .allowed, device: DeviceKind = .iPhone) -> NotificationSectionText {
        NotificationSectionText(
            settings: NotificationSettings(isEnabled: enabled, morningSummaryEnabled: summary, morningSummaryMinute: 540),
            permission: permission,
            device: device
        )
    }

    @Test func switchNamesTheDevice() {
        #expect(section().switchTitle == "Notifications on This iPhone")
        #expect(section(device: .mac).switchTitle == "Notifications on This Mac")
    }

    @Test func deniedPermissionIsExplainedWhileTheSwitchIsOn() {
        let denied = section(true, .denied)
        #expect(denied.showsPermissionProblem)
        #expect(denied.permissionProblem == "Notifications for Scribe are off in Settings. Turn on Allow Notifications there to get alerts.")
        #expect(denied.openSettingsTitle == "Open Settings")
        #expect(section(true, .denied, device: .mac).openSettingsTitle == "Open System Settings")
        #expect(section(true, .denied, device: .mac).permissionProblem.contains("in System Settings"))

        #expect(!section(false, .denied).showsPermissionProblem, "nothing to fix while notifications are off here")
        #expect(!section(true, .allowed).showsPermissionProblem)
        #expect(!section(true, .notDetermined).showsPermissionProblem)
    }

    @Test func summaryRowsFollowTheSwitches() {
        #expect(section(true, summary: true).summaryToggleEnabled)
        #expect(section(true, summary: true).showsSummaryTime)
        #expect(!section(true, summary: false).showsSummaryTime)
        #expect(!section(false, summary: true).summaryToggleEnabled)
        #expect(!section(false, summary: true).showsSummaryTime)
    }

    @Test func footerSaysItIsPerDevice() {
        #expect(section().footer.contains("for this iPhone only"))
        #expect(section(device: .mac).footer.contains("for this Mac only"))
        #expect(section(device: .mac).footer.contains("starts off"), "spec §11: off by default on the Mac")
    }
}

struct SummaryTimeTests {
    nonisolated static let zones = ["Asia/Jerusalem", "Asia/Bangkok", "Europe/Sofia", "America/Sao_Paulo", "Australia/Lord_Howe"]

    @Test(arguments: zones)
    func everyMinuteRoundTrips(zone: String) {
        let calendar = TestCalendar.make(timeZone: zone, firstWeekday: 1)
        var settings = NotificationSettings.iOSDefault
        for minute in 0..<(24 * 60) {
            settings.morningSummaryMinute = minute
            let date = settings.summaryTime(calendar: calendar)
            var copy = NotificationSettings.iOSDefault
            copy.setSummaryTime(date, calendar: calendar)
            #expect(copy.morningSummaryMinute == minute)
        }
    }

    @Test func readsHourAndMinuteOfAnyDate() {
        var settings = NotificationSettings.iOSDefault
        // A picker may hand back a date on another day; only the clock counts.
        settings.setSummaryTime(TestCalendar.date(2026, 3, 27, 7, 45), calendar: TestCalendar.jerusalem)
        #expect(settings.morningSummaryMinute == 7 * 60 + 45)
    }
}

struct SettingsSmallTextTests {
    @Test func exportFilenameUsesTheLocalDay() {
        let lateEvening = TestCalendar.date(2026, 10, 5, 23, 30)
        #expect(ExportDocument.suggestedFilename(now: lateEvening, calendar: TestCalendar.jerusalem) == "Scribe-2026-10-05.json")
        let bangkok = TestCalendar.make(timeZone: "Asia/Bangkok", firstWeekday: 1)
        #expect(ExportDocument.suggestedFilename(now: lateEvening, calendar: bangkok) == "Scribe-2026-10-06.json")
    }

    @Test func versionLine() {
        #expect(AppVersion.text(shortVersion: "0.1", build: "1") == "0.1 (1)")
        #expect(AppVersion.text(shortVersion: "0.1", build: "0.1") == "0.1")
        #expect(AppVersion.text(shortVersion: "0.1", build: nil) == "0.1")
        #expect(AppVersion.text(shortVersion: nil, build: "7") == "Build 7")
        #expect(AppVersion.text(shortVersion: nil, build: nil) == "Unknown")
    }

    @Test func hotkeyNotes() {
        #expect(QuickAddHotkeyNote.menuBar(shortcut: "⌃⇧Space", isTakenBySystem: false) == QuickAddHotkeyNote(text: "⌃⇧Space adds from anywhere", isWarning: false))
        let taken = QuickAddHotkeyNote.menuBar(shortcut: "⌃Space", isTakenBySystem: true)
        #expect(taken.isWarning)
        #expect(taken.text == "⌃Space is also a macOS shortcut, so quick add may not open. Turn that one off in System Settings › Keyboard › Keyboard Shortcuts.")

        #expect(QuickAddHotkeyNote.settings(shortcut: "⌃⇧Space", isTakenBySystem: false) == QuickAddHotkeyNote(text: "Opens quick add from any app.", isWarning: false))
        let takenHere = QuickAddHotkeyNote.settings(shortcut: "⌃Space", isTakenBySystem: true)
        #expect(takenHere.isWarning)
        #expect(takenHere.text.hasSuffix("Keyboard Shortcuts, or record another one here."))
        #expect(QuickAddHotkeyNote.settings(shortcut: nil, isTakenBySystem: false) == QuickAddHotkeyNote(text: "No shortcut. Quick add is still in the menu bar.", isWarning: false))
    }

    @Test func deviceNames() {
        #expect(DeviceKind.iPhone.name == "iPhone")
        #expect(DeviceKind.mac.settingsAppName == "System Settings")
        #if os(macOS)
        #expect(DeviceKind.current == .mac)
        #else
        #expect(DeviceKind.current == .iPhone)
        #endif
    }
}
