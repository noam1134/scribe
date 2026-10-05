import Foundation
import Observation
import ScribeCore

/// Navigation state for the iPhone app: selected tab, the Categories stack,
/// the quick-add sheet, the one row being edited, and error alerts.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case upcoming, categories, search
    }

    enum Destination: Hashable {
        case inbox
        case category(UUID)
    }

    var tab: Tab = .upcoming
    var categoriesPath: [Destination] = []
    var isComposing = false
    var composerCategoryID: UUID?
    /// The row showing its inline editor; one at a time.
    var expandedItemID: UUID?
    var alertMessage: String?

    /// The category on screen, so quick-add files into it by default.
    var visibleCategoryID: UUID? {
        guard tab == .categories, case .category(let id)? = categoriesPath.last else { return nil }
        return id
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
            tab = .categories
            categoriesPath = [item.categoryID.map(Destination.category) ?? .inbox]
            expandedItemID = id
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
