#if DEBUG
import Foundation
import ScribeCore

/// `-uiTesting -demoData` fills the fresh in-memory store with a few
/// categories and items, for looking at the Mac UI. Debug builds only.
@MainActor
enum DemoData {
    static var isRequested: Bool {
        StoreLoader.isUITesting && CommandLine.arguments.contains("-demoData")
    }

    static func seedIfRequested(_ store: any ItemStore) {
        guard isRequested, store.categories.isEmpty else { return }
        let calendar = Calendar.autoupdatingCurrent
        let today = LocalDay(Date(), calendar: calendar)
        func due(_ days: Int, _ minute: Int? = nil) -> DueDate {
            DueDate(day: today.adding(days: days, calendar: calendar), minute: minute)
        }
        do {
            let work = try store.addCategory(CategoryDraft(name: "Work", emoji: "💼", colorName: "blue"))
            let trip = try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭", colorName: "teal"))
            let home = try store.addCategory(CategoryDraft(name: "בית", colorName: "orange"))
            try store.addItem(ItemDraft(title: "Send the quarterly report", categoryID: work, due: due(-1)))
            try store.addItem(ItemDraft(title: "Review Dan’s pull request", categoryID: work, due: due(0, 10 * 60 + 30)))
            try store.addItem(ItemDraft(title: "Book flights to Bangkok", body: "Window seat, morning flight", categoryID: trip, due: due(0)))
            try store.addItem(ItemDraft(title: "Hotel in Chiang Mai", categoryID: trip, due: due(2)))
            try store.addItem(ItemDraft(title: "Passport number", body: "Expires 2031", kind: .memo, categoryID: trip))
            try store.addItem(ItemDraft(title: "לקנות חלב", categoryID: home, due: due(1, 18 * 60)))
            try store.addItem(ItemDraft(title: "ארוחת שבת עם המשפחה", kind: .memo, categoryID: home, due: due(4)))
            let done = try store.addItem(ItemDraft(title: "Renew gym membership", categoryID: home))
            try store.setDone(done, true)
            let orphan = try store.addCategory(CategoryDraft(name: "Old"))
            try store.addItem(ItemDraft(title: "Call the bank", categoryID: orphan))
            try store.deleteCategory(orphan) // leaves an item in the Inbox
        } catch {
            assertionFailure("Demo data: \(error)")
        }
    }

    /// `-demoShow <category name>`, `-demoEdit <item title>` and
    /// `-demoSearch <text>` put the window in a given state.
    static func applyLaunchState(to router: MacRouter) {
        guard isRequested else { return }
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "demoShow"), let category = router.store.categories.first(where: { $0.name == name }) {
            router.sidebar = .category(category.id)
        }
        if let title = defaults.string(forKey: "demoEdit"),
           let item = router.store.items(.search(title)).first(where: { $0.title == title }) {
            router.open(.item(item.id))
        }
        if let text = defaults.string(forKey: "demoSearch") {
            router.searchText = text
        }
    }
}
#endif
