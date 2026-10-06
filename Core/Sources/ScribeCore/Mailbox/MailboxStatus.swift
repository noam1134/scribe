import Foundation

/// How this device's last talks with the Claude mailbox went. Per device
/// (standard defaults), never synced.
public struct MailboxStatus: Codable, Equatable, Sendable {
    public static let defaultsKey = "mailbox.status"

    /// The end of the latest sync that went through.
    public private(set) var lastSuccess: Date?
    /// Set while syncs keep failing; any success clears it.
    public private(set) var failure: MailboxFailure?

    public init() {}

    public mutating func succeeded(at date: Date) {
        if lastSuccess.map({ $0 < date }) ?? true { lastSuccess = date }
        failure = nil
    }

    public mutating func failed(_ failure: MailboxFailure) {
        self.failure = failure
    }

    public init(from defaults: UserDefaults, key: String = defaultsKey) {
        guard let data = defaults.data(forKey: key),
              let status = try? JSONDecoder().decode(MailboxStatus.self, from: data) else {
            self.init()
            return
        }
        self = status
    }

    public func save(to defaults: UserDefaults, key: String = defaultsKey) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }
}

/// The Claude section of Settings.
public struct MailboxStatusText: Equatable, Sendable {
    /// "Last synced at 09:14", "Syncing…", "Not synced yet".
    public var line: String
    /// Why the last sync failed, if it did.
    public var problem: String?

    public init(status: MailboxStatus, isSyncing: Bool, now: Date, labels: DueLabels = DueLabels()) {
        if isSyncing {
            line = "Syncing…"
        } else if let last = status.lastSuccess {
            line = "Last synced \(SyncStatusText.when(last, now: now, labels: labels))"
        } else {
            line = "Not synced yet"
        }
        problem = status.failure.map(Self.sentence(for:))
    }

    public static let footer = "Lets Claude add tasks and memos to Scribe and see what’s coming up, from any device. Paste the link of the Scribe connector you added in Claude."

    /// Under the link field when Connect can't read it.
    public static let linkProblem = "That isn’t a mailbox link. Paste the connector’s link from Claude: https://…/<key>/mcp"

    private static func sentence(for failure: MailboxFailure) -> String {
        switch failure {
        case .offline:
            "Couldn’t reach the mailbox — offline? Scribe tries again when it’s opened."
        case .linkRejected:
            "The mailbox didn’t accept this link. Check it matches the Scribe connector in Claude, or disconnect and paste it again."
        case .server(let code) where code > 0:
            "The mailbox answered with an error (\(code)). Scribe tries again when it’s opened."
        case .server:
            "Something went wrong talking to the mailbox. Scribe tries again when it’s opened."
        case .unreadable:
            "Scribe couldn’t read the mailbox’s answer. The mailbox may be newer than this version of Scribe."
        }
    }
}
