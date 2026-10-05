import Foundation

/// What to change so the pending notifications match a plan. Requests the
/// planner doesn't own are never touched.
public struct NotificationDiff: Equatable, Sendable {
    /// A request already pending in the notification center.
    public struct Pending: Equatable, Sendable {
        public var id: String
        /// `PlannedNotification.fingerprint` stored when it was scheduled.
        public var fingerprint: String?

        public init(id: String, fingerprint: String?) {
            self.id = id
            self.fingerprint = fingerprint
        }
    }

    /// Pending planner requests that are no longer planned, sorted.
    public let remove: [String]
    /// Planned requests that are missing or changed, in plan order. Adding a
    /// request whose id is pending replaces it.
    public let add: [PlannedNotification]

    public var isEmpty: Bool { remove.isEmpty && add.isEmpty }

    public init(pending: [Pending], planned: [PlannedNotification]) {
        let ours = pending.filter { PlannedNotification.isPlannerIdentifier($0.id) }
        let fingerprints = Dictionary(ours.map { ($0.id, $0.fingerprint) }, uniquingKeysWith: { first, _ in first })
        let plannedIDs = Set(planned.map(\.id))
        remove = Set(ours.map(\.id)).subtracting(plannedIDs).sorted()
        add = planned.filter { request in
            guard let stored = fingerprints[request.id] else { return true }
            return stored != request.fingerprint
        }
    }
}
