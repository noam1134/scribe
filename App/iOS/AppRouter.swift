import Foundation
import Observation
import ScribeCore

/// Navigation state for the iPhone app: selected tab, the Lists screen's
/// state, the quick-add sheet, the one row being edited, and error alerts.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case lists, upcoming, search
    }

    var tab: Tab = .lists
    var isComposing = false
    var composerCategoryID: UUID?
    /// The row showing its inline editor; one at a time.
    var expandedItemID: UUID?
    var alertMessage: String?

    /// Collapsed sections and Show Completed, kept on this device (spec §20).
    var lists: ListsPreferences {
        didSet { lists.save(to: Self.preferences) }
    }
    /// Lists shows only the category rows, to reorder, edit and delete them.
    var isEditingLists = false
    /// The row Lists scrolls to once it has laid out (an item link).
    var listsScrollTarget: UUID?

    /// UI tests start from the defaults on every launch.
    private static let preferences: UserDefaults = {
        guard StoreLoader.isUITesting else { return .standard }
        let name = "com.noamchuri.scribe.uitesting"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }()

    init() {
        lists = ListsPreferences(from: Self.preferences)
    }

    func compose(in categoryID: UUID?) {
        composerCategoryID = categoryID
        isComposing = true
    }

    func open(_ link: DeepLink, store: any ItemStore) {
        switch link {
        case .upcoming:
            // A composer left open (e.g. after the widget's "+") would hide it.
            isComposing = false
            tab = .upcoming
        case .add(let categoryID):
            compose(in: categoryID)
        case .item(let id):
            guard let item = store.item(id) else { return }
            isComposing = false
            tab = .lists
            isEditingLists = false
            lists.expand(ListSections.sectionID(for: item, categories: store.categories))
            // A done item stays on screen while its editor is open.
            expandedItemID = id
            listsScrollTarget = id
        }
    }

    /// Runs a store write; failures become an alert instead of vanishing.
    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
