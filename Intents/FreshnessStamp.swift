import Foundation
import ScribeCore

/// When the app last knew the shared store matched iCloud (spec §18): after
/// an iCloud import, and on iPhone when it leaves the foreground (while in
/// front it gets iCloud's pushes). Only the app writes it; widgets read it
/// to say "Updated 09:14" once it's old. Lives in the App Group defaults.
enum FreshnessStamp {
    private static let key = "dataFreshAt"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: ScribeIDs.appGroup) }

    static var date: Date? { defaults?.object(forKey: key) as? Date }

    /// Never moves backwards.
    static func record(_ date: Date = Date()) {
        guard let defaults else { return }
        if let current = defaults.object(forKey: key) as? Date, current >= date { return }
        defaults.set(date, forKey: key)
    }
}
