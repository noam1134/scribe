#if DEBUG
import Foundation
import ScribeCore

/// Settings states for UI tests and screenshots, in `-uiTesting` runs only
/// (no iCloud, notifications inactive). Debug builds only.
///
/// - `-demoSync signedIn | offline | signedOut | checking` — the iCloud row.
/// - `-demoPermission denied | allowed | notDetermined` — notification permission.
/// - `-showSettings` — Settings open at launch.
@MainActor
enum SettingsDemo {
    private static var isActive: Bool { StoreLoader.isUITesting }

    private static func value(_ key: String) -> String? {
        isActive ? UserDefaults.standard.string(forKey: key) : nil
    }

    static var sync: (CloudAccountState, SyncLog)? {
        let now = Date()
        func synced(minutesAgo: Double) -> SyncEvent {
            SyncEvent(kind: .import, endDate: now.addingTimeInterval(-minutesAgo * 60), failure: nil)
        }
        var log = SyncLog()
        switch value("demoSync") {
        case "signedIn":
            log.record(synced(minutesAgo: 4))
            return (.available, log)
        case "offline":
            log.record(synced(minutesAgo: 95))
            log.record(SyncEvent(kind: .export, endDate: now.addingTimeInterval(-60), failure: .offline))
            return (.available, log)
        case "signedOut":
            return (.noAccount, log)
        case "checking":
            return (.checking, log)
        default:
            return nil
        }
    }

    static var permission: NotificationPermission? {
        switch value("demoPermission") {
        case "denied": .denied
        case "allowed": .allowed
        case "notDetermined": .notDetermined
        default: nil
        }
    }

    static var showsSettingsAtLaunch: Bool {
        isActive && CommandLine.arguments.contains("-showSettings")
    }
}
#endif
