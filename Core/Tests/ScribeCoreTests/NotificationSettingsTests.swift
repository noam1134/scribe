import Foundation
import Testing
@testable import ScribeCore

struct NotificationSettingsTests {
    /// A throwaway defaults domain per test.
    func freshDefaults() -> UserDefaults {
        let name = "scribe-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func platformDefaultsFollowTheSpec() {
        // Spec §11: on for iOS, off for macOS (avoids double alerts); summary at 09:00.
        #expect(NotificationSettings.iOSDefault == NotificationSettings(isEnabled: true, morningSummaryEnabled: true, morningSummaryMinute: 540))
        #expect(NotificationSettings.macOSDefault == NotificationSettings(isEnabled: false, morningSummaryEnabled: true, morningSummaryMinute: 540))
        #if os(macOS)
        #expect(NotificationSettings.platformDefault == .macOSDefault)
        #else
        #expect(NotificationSettings.platformDefault == .iOSDefault)
        #endif
    }

    @Test func missingKeysFallBack() {
        let defaults = freshDefaults()
        #expect(NotificationSettings(from: defaults, fallback: .iOSDefault) == .iOSDefault)
        #expect(NotificationSettings(from: defaults, fallback: .macOSDefault) == .macOSDefault)
    }

    @Test func roundTrip() {
        let defaults = freshDefaults()
        let custom = NotificationSettings(isEnabled: false, morningSummaryEnabled: false, morningSummaryMinute: 7 * 60 + 30)
        custom.save(to: defaults)
        #expect(NotificationSettings(from: defaults, fallback: .iOSDefault) == custom)
    }

    @Test func eachKeyFallsBackOnItsOwn() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: NotificationSettings.Keys.isEnabled)
        let loaded = NotificationSettings(from: defaults, fallback: .iOSDefault)
        #expect(loaded == NotificationSettings(isEnabled: false, morningSummaryEnabled: true, morningSummaryMinute: 540))
    }

    @Test(arguments: [-1, 1440, 99_999])
    func outOfRangeSummaryMinuteFallsBack(minute: Int) {
        let defaults = freshDefaults()
        defaults.set(minute, forKey: NotificationSettings.Keys.morningSummaryMinute)
        #expect(NotificationSettings(from: defaults, fallback: .iOSDefault).morningSummaryMinute == 540)
    }

    @Test func midnightIsAValidSummaryTime() {
        let defaults = freshDefaults()
        defaults.set(0, forKey: NotificationSettings.Keys.morningSummaryMinute)
        #expect(NotificationSettings(from: defaults, fallback: .iOSDefault).morningSummaryMinute == 0)
    }
}
