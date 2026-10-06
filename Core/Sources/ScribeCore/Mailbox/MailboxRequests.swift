import Foundation

/// Why talking to the mailbox failed, in the terms Settings explains.
public enum MailboxFailure: Error, Codable, Equatable, Sendable {
    /// No connection, or the Worker couldn't be reached in time.
    case offline
    /// 404: the link (its key) isn't the deployment's, or the Worker is gone.
    case linkRejected
    /// Any other HTTP status.
    case server(Int)
    /// The answer wasn't what Scribe expects (a newer Worker?).
    case unreadable

    /// Classifies anything a request threw.
    public init(_ error: any Error) {
        if let failure = error as? MailboxFailure {
            self = failure
        } else if error is DecodingError {
            self = .unreadable
        } else if (error as NSError).domain == NSURLErrorDomain {
            self = .offline
        } else {
            self = .server(0)
        }
    }
}

/// The HTTP requests of the app's side of the mailbox (`mailbox/README.md`).
public enum MailboxRequests {
    /// Short: background refresh has about 30 seconds for everything.
    public static let timeout: TimeInterval = 10

    public static func publish(_ snapshot: MailboxSnapshot, to connection: MailboxConnection) throws -> URLRequest {
        var request = base(connection.url(.snapshot), method: "PUT")
        request.httpBody = try MailboxSnapshot.encoder().encode(snapshot)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    public static func inbox(_ connection: MailboxConnection) -> URLRequest {
        base(connection.url(.inbox), method: "GET")
    }

    public static func acknowledge(_ ids: [String], to connection: MailboxConnection) throws -> URLRequest {
        var request = base(connection.url(.ack), method: "POST")
        request.httpBody = try JSONEncoder().encode(MailboxAck(ids: ids))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Throws the failure a status code means; 2xx passes.
    public static func check(status: Int) throws {
        switch status {
        case 200..<300: return
        case 404: throw MailboxFailure.linkRejected
        default: throw MailboxFailure.server(status)
        }
    }

    public static func decodeInbox(_ data: Data) throws -> [MailboxItem] {
        do {
            return try JSONDecoder().decode(MailboxInbox.self, from: data).items
        } catch {
            throw MailboxFailure.unreadable
        }
    }

    private static func base(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
