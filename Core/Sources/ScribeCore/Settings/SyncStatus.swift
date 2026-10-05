import Foundation

/// The device's iCloud account as CloudKit reports it (spec §13). The app
/// maps `CKAccountStatus` onto this.
public enum CloudAccountState: Equatable, Sendable {
    /// Not asked yet.
    case checking
    case available
    /// Not signed in, or iCloud is off for Scribe.
    case noAccount
    /// Screen Time or a device profile blocks iCloud.
    case restricted
    /// Signed in, but the account needs attention (e.g. a password).
    case temporarilyUnavailable
    /// CloudKit couldn't tell.
    case unknown
}

/// The three kinds of event `NSPersistentCloudKitContainer` reports (spec §18).
public enum SyncEventKind: String, Codable, Sendable {
    case setup
    case `import`
    case export
}

/// Why a sync event failed, in the terms Settings explains.
public enum SyncFailureReason: Codable, Equatable, Sendable {
    case offline
    case iCloudBusy
    case notSignedIn
    case storageFull
    case accountNeedsAttention
    /// Anything else: its error domain and code, e.g. "CKErrorDomain 15".
    case other(String)
    /// It failed without saying why.
    case unexplained

    /// Nil for an operation the system cancelled — not a failure to show.
    init?(error: NSError) {
        guard let reason = Self.classify(error) else { return nil }
        self = reason
    }

    private static let cloudKitDomain = "CKErrorDomain"
    private static let cloudKitCancelled = 20
    /// `CKPartialErrorsByItemIDKey`.
    private static let partialErrorsKey = "CKPartialErrors"
    /// Core Data's "Unable to initialize without an iCloud account".
    private static let coreDataNoAccount = 134400

    private static func classify(_ error: NSError) -> SyncFailureReason? {
        if error.domain == cloudKitDomain {
            switch error.code {
            case cloudKitCancelled:
                return nil
            case 2: // partial failure: the most telling of the per-record errors
                let inner = (error.userInfo[partialErrorsKey] as? [AnyHashable: Any])?.values.compactMap { $0 as? NSError } ?? []
                if let best = inner.compactMap(classify).filter(\.isSpecific).min(by: { $0.priority < $1.priority }) {
                    return best
                }
            case 3, 4: return .offline
            case 6, 7, 23, 34: return .iCloudBusy // service unavailable, rate limited, zone busy, response lost
            case 9: return .notSignedIn
            case 25: return .storageFull
            case 32, 36: return .accountNeedsAttention // managed account restricted, temporarily unavailable
            default: break
            }
        } else if error.domain == NSURLErrorDomain {
            return .offline
        } else if error.domain == NSCocoaErrorDomain, error.code == coreDataNoAccount {
            return .notSignedIn
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            // A cancellation wrapped in another error is still a cancellation.
            guard let reason = classify(underlying) else { return nil }
            if reason.isSpecific { return reason }
        }
        return .other("\(error.domain) \(error.code)")
    }

    /// Offline or iCloud busy: any sync that works afterwards proves it's over.
    var isConnectionTrouble: Bool {
        self == .offline || self == .iCloudBusy
    }

    private var isSpecific: Bool {
        switch self {
        case .other, .unexplained: false
        default: true
        }
    }

    /// Lower is more useful to the reader.
    private var priority: Int {
        switch self {
        case .notSignedIn: 0
        case .accountNeedsAttention: 1
        case .storageFull: 2
        case .offline: 3
        case .iCloudBusy: 4
        case .other, .unexplained: 5
        }
    }
}

/// A finished sync event, reduced to what Settings needs.
public struct SyncEvent: Equatable, Sendable {
    public var kind: SyncEventKind
    public var endDate: Date
    /// Nil when it succeeded.
    public var failure: SyncFailureReason?

    public init(kind: SyncEventKind, endDate: Date, failure: SyncFailureReason?) {
        self.kind = kind
        self.endDate = endDate
        self.failure = failure
    }

    /// From a CloudKit event's outcome. Nil for an operation the system
    /// cancelled, which says nothing about whether sync works.
    public init?(kind: SyncEventKind, endDate: Date, succeeded: Bool, error: NSError?) {
        if succeeded {
            self.init(kind: kind, endDate: endDate, failure: nil)
        } else if let error {
            guard let reason = SyncFailureReason(error: error) else { return nil }
            self.init(kind: kind, endDate: endDate, failure: reason)
        } else {
            self.init(kind: kind, endDate: endDate, failure: .unexplained)
        }
    }
}

public struct SyncFailure: Codable, Equatable, Sendable {
    public var kind: SyncEventKind
    public var date: Date
    public var reason: SyncFailureReason

    public init(kind: SyncEventKind, date: Date, reason: SyncFailureReason) {
        self.kind = kind
        self.date = date
        self.reason = reason
    }
}

/// What this device knows about its sync (spec §13, §18): when it last
/// synced, and which kinds of event are failing. Saved per device, never
/// synced.
public struct SyncLog: Codable, Equatable, Sendable {
    /// The end of the latest successful import or export. Setup alone
    /// doesn't move data, so it doesn't count.
    public private(set) var lastSuccess: Date?
    /// At most one per kind: that kind's latest event failed and nothing
    /// that clears it has succeeded since.
    public private(set) var failures: [SyncFailure] = []
    /// The iCloud account this log describes (CloudKit's user record name
    /// for Scribe's container). Nil until one has been seen.
    public private(set) var accountID: String?

    public init() {}

    public var latestFailure: SyncFailure? {
        failures.max { $0.date < $1.date }
    }

    /// Returns whether anything changed.
    @discardableResult
    public mutating func record(_ event: SyncEvent) -> Bool {
        let before = self
        if let reason = event.failure {
            failures.removeAll { $0.kind == event.kind }
            failures.append(SyncFailure(kind: event.kind, date: event.endDate, reason: reason))
        } else {
            if event.kind != .setup, lastSuccess.map({ $0 < event.endDate }) ?? true {
                lastSuccess = event.endDate
            }
            let synced = event.kind != .setup
            failures.removeAll { failure in
                guard failure.date <= event.endDate else { return false }
                // Its own kind works again. A sync also proves setup worked
                // and the connection is back, whichever way it went.
                return failure.kind == event.kind
                    || (synced && (failure.kind == .setup || failure.reason.isConnectionTrouble))
            }
        }
        return self != before
    }

    /// What the app learned about the account (`previous` is what it knew
    /// before, in this process). "Last synced" must not describe another
    /// account, so the log starts over when the account is a different one,
    /// or when a sign-in was seen and the account can't be told. Signing
    /// out keeps it. Returns whether anything changed.
    @discardableResult
    public mutating func accountChecked(previous: CloudAccountState, current: CloudAccountState, identity: String?) -> Bool {
        guard current == .available else { return false }
        let signedIn = previous == .noAccount
        let before = self
        if let identity {
            let isOther = accountID.map { $0 != identity } ?? signedIn
            if isOther { self = SyncLog() }
            accountID = identity
        } else if signedIn {
            self = SyncLog()
        }
        return self != before
    }

    public static let defaultsKey = "sync.log"

    /// The saved log, or an empty one if there is none or it can't be read.
    public init(from defaults: UserDefaults, key: String = defaultsKey) {
        guard let data = defaults.data(forKey: key),
              let log = try? JSONDecoder().decode(SyncLog.self, from: data) else {
            self.init()
            return
        }
        self = log
    }

    public func save(to defaults: UserDefaults, key: String = defaultsKey) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }
}
