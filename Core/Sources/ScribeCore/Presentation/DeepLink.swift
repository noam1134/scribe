import Foundation

/// `scribe://` URLs used by widgets, controls and the app itself (spec §8).
public enum DeepLink: Hashable, Sendable {
    /// Open the quick-add composer, optionally preselecting a category.
    case add(categoryID: UUID?)
    /// Show one item.
    case item(UUID)
    /// Show the Upcoming agenda.
    case upcoming

    public static let scheme = "scribe"

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "add":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let category = query.first { $0.name == "category" }?.value.flatMap(UUID.init(uuidString:))
            self = .add(categoryID: category)
        case "item":
            guard path.count == 1, let id = UUID(uuidString: path[0]) else { return nil }
            self = .item(id)
        case "upcoming":
            self = .upcoming
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .add(let categoryID):
            components.host = "add"
            if let categoryID {
                components.queryItems = [URLQueryItem(name: "category", value: categoryID.uuidString)]
            }
        case .item(let id):
            components.host = "item"
            components.path = "/" + id.uuidString
        case .upcoming:
            components.host = "upcoming"
        }
        return components.url!
    }
}
