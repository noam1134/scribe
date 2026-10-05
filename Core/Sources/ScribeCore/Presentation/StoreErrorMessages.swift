import Foundation

/// What the UI says when the store refuses a write (spec §13).
extension StoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "Give it a title first."
        case .emptyCategoryName: "Give the category a name."
        case .duplicateCategoryName: "There’s already a category with that name."
        case .invalidColorName(let name): "“\(name)” isn’t one of the category colors."
        case .itemNotFound: "That item no longer exists. It may have been deleted on another device."
        case .categoryNotFound: "That category no longer exists. It may have been deleted on another device."
        }
    }
}
