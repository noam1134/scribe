import Foundation

/// Per-device notification preferences (spec §11). Stored locally, never
/// synced: the iPhone alerts by default and the Mac doesn't, so one reminder
/// doesn't ring twice.
public struct NotificationSettings: Equatable, Sendable {
    /// Master switch: item alerts and the morning summary.
    public var isEnabled: Bool
    public var morningSummaryEnabled: Bool
    /// When the morning summary arrives, in minutes after local midnight.
    public var morningSummaryMinute: Int

    public init(isEnabled: Bool, morningSummaryEnabled: Bool, morningSummaryMinute: Int) {
        precondition((0..<1440).contains(morningSummaryMinute), "morningSummaryMinute must be in 0..<1440")
        self.isEnabled = isEnabled
        self.morningSummaryEnabled = morningSummaryEnabled
        self.morningSummaryMinute = morningSummaryMinute
    }

    public static let iOSDefault = NotificationSettings(isEnabled: true, morningSummaryEnabled: true, morningSummaryMinute: 9 * 60)
    public static let macOSDefault = NotificationSettings(isEnabled: false, morningSummaryEnabled: true, morningSummaryMinute: 9 * 60)

    public static var platformDefault: NotificationSettings {
        #if os(macOS)
        macOSDefault
        #else
        iOSDefault
        #endif
    }

    public enum Keys {
        public static let isEnabled = "notifications.enabled"
        public static let morningSummaryEnabled = "notifications.morningSummary"
        public static let morningSummaryMinute = "notifications.morningSummaryMinute"
    }

    /// Reads each value on its own; a missing or invalid one takes `fallback`'s.
    /// Values may also come from launch arguments
    /// (`-notifications.morningSummaryMinute 450`), which arrive as strings.
    public init(from defaults: UserDefaults, fallback: NotificationSettings = .platformDefault) {
        func bool(_ key: String) -> Bool? {
            switch defaults.object(forKey: key) {
            case let value as Bool: value
            case let text as String: ["yes", "true", "1"].contains(text.lowercased()) ? true : ["no", "false", "0"].contains(text.lowercased()) ? false : nil
            default: nil
            }
        }
        func minute(_ key: String) -> Int? {
            let value: Int? = switch defaults.object(forKey: key) {
            case let number as Int: number
            case let text as String: Int(text)
            default: nil
            }
            return value.flatMap { (0..<1440).contains($0) ? $0 : nil }
        }
        self.init(
            isEnabled: bool(Keys.isEnabled) ?? fallback.isEnabled,
            morningSummaryEnabled: bool(Keys.morningSummaryEnabled) ?? fallback.morningSummaryEnabled,
            morningSummaryMinute: minute(Keys.morningSummaryMinute) ?? fallback.morningSummaryMinute
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        defaults.set(morningSummaryEnabled, forKey: Keys.morningSummaryEnabled)
        defaults.set(morningSummaryMinute, forKey: Keys.morningSummaryMinute)
    }
}
