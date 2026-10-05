import Foundation

/// Which device the sentences are for: Settings names it ("this iPhone") and
/// its settings app.
public enum DeviceKind: Sendable {
    case iPhone
    case mac

    public static var current: DeviceKind {
        #if os(macOS)
        .mac
        #else
        .iPhone
        #endif
    }

    public var name: String {
        switch self {
        case .iPhone: "iPhone"
        case .mac: "Mac"
        }
    }

    public var settingsAppName: String {
        switch self {
        case .iPhone: "Settings"
        case .mac: "System Settings"
        }
    }
}

/// The iCloud section of Settings (spec §13, §18).
public struct SyncStatusText: Equatable, Sendable {
    public enum Symbol: Sendable {
        case on, off, warning, checking
    }

    public var symbol: Symbol
    public var headline: String
    /// How to fix it, when sync is off.
    public var detail: String?
    /// "Last synced at 09:14".
    public var lastSynced: String?
    /// The failing sync, unless the account row already explains it.
    public var problem: String?

    public init(account: CloudAccountState, log: SyncLog, now: Date, device: DeviceKind, labels: DueLabels = DueLabels()) {
        let here = "this \(device.name)"
        switch account {
        case .checking:
            symbol = .checking
            headline = "Checking iCloud…"
            detail = nil
        case .available:
            symbol = .on
            headline = "Syncing with iCloud"
            detail = nil
        case .noAccount:
            symbol = .off
            headline = "Sync off — sign in to iCloud"
            detail = "Open \(device.settingsAppName), sign in with your Apple Account and make sure iCloud is on for Scribe. Until then everything stays on \(here); nothing is lost."
        case .restricted:
            symbol = .off
            headline = "iCloud is restricted on \(here)"
            detail = "Screen Time or a device profile blocks iCloud. Everything stays on \(here)."
        case .temporarilyUnavailable:
            symbol = .warning
            headline = "iCloud needs attention"
            detail = "Open \(device.settingsAppName) and check your Apple Account — iCloud may need your password. Sync picks up again by itself."
        case .unknown:
            symbol = .warning
            headline = "Couldn’t check iCloud"
            detail = "Sync carries on by itself whenever iCloud is available."
        }

        if let last = log.lastSuccess {
            lastSynced = "Last synced \(Self.when(last, now: now, labels: labels))"
        } else if account == .available {
            lastSynced = "Not synced yet on \(here)"
        } else {
            lastSynced = nil
        }

        let accountExplains = [.noAccount, .restricted, .temporarilyUnavailable].contains(account)
        if !accountExplains, let failure = log.latestFailure {
            problem = Self.sentence(for: failure, device: device)
            if symbol == .on { symbol = .warning }
        } else {
            problem = nil
        }
    }

    /// "just now", "at 09:14", "yesterday at 22:10", "Fri 2 Oct at 09:05".
    private static func when(_ date: Date, now: Date, labels: DueLabels) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let calendar = labels.calendar
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        let time = labels.time((clock.hour ?? 0) * 60 + (clock.minute ?? 0))
        let day = LocalDay(date, calendar: calendar)
        let today = LocalDay(now, calendar: calendar)
        switch day {
        case today: return "at \(time)"
        case today.adding(days: -1, calendar: calendar): return "yesterday at \(time)"
        default: return "\(labels.dayTitle(day, today: today)) at \(time)"
        }
    }

    private static func sentence(for failure: SyncFailure, device: DeviceKind) -> String {
        switch failure.reason {
        case .offline:
            "Offline — changes are saved on this \(device.name) and upload once it’s back online."
        case .iCloudBusy:
            "iCloud is busy — Scribe will try again shortly."
        case .notSignedIn:
            "iCloud didn’t accept the sign-in. Check your Apple Account in \(device.settingsAppName)."
        case .storageFull:
            "Your iCloud storage is full — changes stay on this \(device.name) until there’s room."
        case .accountNeedsAttention:
            "iCloud needs attention — check your Apple Account in \(device.settingsAppName)."
        case .other(let code):
            switch failure.kind {
            case .setup: "iCloud sync couldn’t start (\(code)). Scribe will try again."
            case .import: "The last download from iCloud failed (\(code)). Scribe will try again."
            case .export: "The last upload to iCloud failed (\(code)). Scribe will try again."
            }
        }
    }
}

/// The Notifications section of Settings (spec §11, §13).
public struct NotificationSectionText: Equatable, Sendable {
    public var switchTitle: String
    /// Permission is denied while notifications are wanted on this device.
    public var showsPermissionProblem: Bool
    public var permissionProblem: String
    public var openSettingsTitle: String
    public var summaryToggleEnabled: Bool
    public var showsSummaryTime: Bool
    public var footer: String

    public init(settings: NotificationSettings, permission: NotificationPermission, device: DeviceKind) {
        switchTitle = "Notifications on This \(device.name)"
        showsPermissionProblem = settings.isEnabled && permission == .denied
        permissionProblem = "Notifications for Scribe are off in \(device.settingsAppName). Turn on Allow Notifications there to get alerts."
        openSettingsTitle = "Open \(device.settingsAppName)"
        summaryToggleEnabled = settings.isEnabled
        showsSummaryTime = settings.isEnabled && settings.morningSummaryEnabled
        let what = "Alerts at each item’s time, and a morning summary on days with something due."
        footer = switch device {
        case .iPhone: "\(what) This switch is for this iPhone only."
        case .mac: "\(what) This switch is for this Mac only — it starts off so reminders don’t ring on both devices."
        }
    }
}

extension NotificationSettings {
    /// A fixed day without daylight-saving changes, so editing the time in a
    /// picker can't shift it.
    private static let summaryReferenceDay = LocalDay(2001, 1, 1)

    /// The summary time as a date, for a time picker.
    public func summaryTime(calendar: Calendar) -> Date {
        Self.summaryReferenceDay.date(atMinute: morningSummaryMinute, calendar: calendar)
    }

    /// Takes the hour and minute of a picked date (its day doesn't matter).
    public mutating func setSummaryTime(_ date: Date, calendar: Calendar) {
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        morningSummaryMinute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
    }
}

extension ExportDocument {
    /// "Scribe-2026-10-05.json", on the device's local day.
    public static func suggestedFilename(now: Date, calendar: Calendar) -> String {
        "Scribe-\(LocalDay(now, calendar: calendar).isoString).json"
    }
}

public enum AppVersion {
    /// "0.1 (1)" from `CFBundleShortVersionString` and `CFBundleVersion`.
    public static func text(shortVersion: String?, build: String?) -> String {
        switch (shortVersion, build) {
        case let (version?, build?) where build != version: "\(version) (\(build))"
        case let (version?, _): version
        case let (nil, build?): "Build \(build)"
        case (nil, nil): "Unknown"
        }
    }
}

/// The line under the quick-add shortcut (spec §8, §19), in the menu bar
/// and in the Mac's Settings. macOS gets a shortcut it also uses first.
public struct QuickAddHotkeyNote: Equatable, Sendable {
    public var text: String
    public var isWarning: Bool

    public init(text: String, isWarning: Bool) {
        self.text = text
        self.isWarning = isWarning
    }

    private static func taken(_ shortcut: String) -> String {
        "\(shortcut) is also a macOS shortcut, so quick add may not open. Turn that one off in System Settings › Keyboard › Keyboard Shortcuts"
    }

    public static func menuBar(shortcut: String, isTakenBySystem: Bool) -> QuickAddHotkeyNote {
        isTakenBySystem
            ? QuickAddHotkeyNote(text: taken(shortcut) + ".", isWarning: true)
            : QuickAddHotkeyNote(text: "\(shortcut) adds from anywhere", isWarning: false)
    }

    public static func settings(shortcut: String?, isTakenBySystem: Bool) -> QuickAddHotkeyNote {
        guard let shortcut else {
            return QuickAddHotkeyNote(text: "No shortcut. Quick add is still in the menu bar.", isWarning: false)
        }
        return isTakenBySystem
            ? QuickAddHotkeyNote(text: taken(shortcut) + ", or record another one here.", isWarning: true)
            : QuickAddHotkeyNote(text: "Opens quick add from any app.", isWarning: false)
    }
}
