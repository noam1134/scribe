import Foundation

/// Where the Claude mailbox lives, read from the connector link the user
/// added in Claude (`https://<worker>/<key>/mcp`): the Worker's address and
/// the secret key every route sits under.
public struct MailboxConnection: Equatable, Sendable {
    /// `https://<worker>`, without a path.
    public let baseURL: URL
    public let key: String

    /// The Worker refuses shorter keys.
    public static let minimumKeyLength = 32

    /// Accepts the link as Claude has it, with or without the trailing
    /// `/mcp`, surrounding spaces or a trailing slash. Only https, except
    /// for a Worker running locally (`wrangler dev`).
    public init?(link: String) {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let isLocal = ["localhost", "127.0.0.1"].contains(host.lowercased())
        guard scheme == "https" || (scheme == "http" && isLocal) else { return nil }

        var segments = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if segments.last == "mcp" { segments.removeLast() }
        guard segments.count == 1, let key = segments.first, Self.isKey(key) else { return nil }

        var base = URLComponents()
        base.scheme = scheme
        base.host = host
        base.port = components.port
        guard let url = base.url else { return nil }
        baseURL = url
        self.key = key
    }

    /// The link Claude uses (and the one the user pasted).
    public var link: String {
        baseURL.appending(path: key).appending(path: "mcp").absoluteString
    }

    /// The Worker's host name, safe to show: it isn't the secret.
    public var host: String {
        baseURL.host() ?? baseURL.absoluteString
    }

    public enum Endpoint: Sendable {
        case snapshot
        case inbox
        case ack
    }

    public func url(_ endpoint: Endpoint) -> URL {
        let app = baseURL.appending(path: key).appending(path: "app")
        return switch endpoint {
        case .snapshot: app.appending(path: "snapshot")
        case .inbox: app.appending(path: "inbox")
        case .ack: app.appending(path: "inbox").appending(path: "ack")
        }
    }

    private static func isKey(_ text: String) -> Bool {
        text.count >= minimumKeyLength && text.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
        }
    }
}
