import Foundation
import ScribeCore

extension ItemSnapshot {
    /// The line under a row's title: "Fri, 9 Oct · 18:00 · 🇹🇭 Thailand".
    /// Under a day header only the time is worth repeating.
    func subtitle(category: CategorySnapshot?, showsDay: Bool, showsCategory: Bool) -> String? {
        var parts: [String] = []
        if let due {
            let labels = DueLabels()
            let today = LocalDay(Date(), calendar: labels.calendar)
            if showsDay {
                parts.append(labels.due(due, today: today))
            } else if let minute = due.minute {
                parts.append(labels.time(minute))
            }
        }
        if showsCategory, let category { parts.append(category.displayName) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
