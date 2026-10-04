import Foundation
import SwiftData

/// Persisted item. CloudKit rules: every property has a default or is
/// optional, nothing is unique, relationships are optional. After the
/// CloudKit schema ships to production, only ADD fields — never rename,
/// retype or remove one.
@Model
public final class Item {
    public var id: UUID = UUID()
    public var title: String = ""
    public var body: String = ""
    public var kindRaw: String = ItemKind.task.rawValue
    public var category: Category?
    /// Floating day, "yyyy-MM-dd".
    public var dueDay: String?
    /// Minutes after local midnight; only meaningful with `dueDay`.
    public var dueMinute: Int?
    public var isDone: Bool = false
    public var doneAt: Date?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        kind: ItemKind = .task,
        due: DueDate? = nil,
        isDone: Bool = false,
        doneAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.kindRaw = kind.rawValue
        self.dueDay = due?.day.isoString
        self.dueMinute = due?.minute
        self.isDone = isDone
        self.doneAt = doneAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .task }
        set { kindRaw = newValue.rawValue }
    }

    public var due: DueDate? {
        get {
            guard let dueDay, let day = LocalDay(isoString: dueDay) else { return nil }
            let minute = dueMinute.flatMap { (0..<1440).contains($0) ? $0 : nil }
            return DueDate(day: day, minute: minute)
        }
        set {
            dueDay = newValue?.day.isoString
            dueMinute = newValue?.minute
        }
    }
}
