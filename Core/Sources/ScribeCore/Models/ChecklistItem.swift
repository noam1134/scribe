import Foundation

/// One step of an item's checklist ("Pack for Borovets" → boots, gloves,
/// passport). The whole list is stored as JSON in `Item.checklistJSON`, so
/// sync is last-writer-wins for the list as a whole.
public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }

    /// A step written by a later version may lack a field; it still reads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
    }
}

/// `Item.checklistJSON` ⇄ steps. Never throws: unreadable JSON reads as no
/// steps, and an unreadable step is skipped.
public enum ChecklistCoding {
    public static func decode(_ json: String) -> [ChecklistItem] {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([Lenient].self, from: data) else { return [] }
        return steps.compactMap(\.step)
    }

    /// "" for no steps, so an item without a checklist keeps the default.
    public static func encode(_ steps: [ChecklistItem]) -> String {
        guard !steps.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(steps) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private struct Lenient: Decodable {
        let step: ChecklistItem?

        init(from decoder: any Decoder) throws {
            step = try? ChecklistItem(from: decoder)
        }
    }
}

extension Item {
    var checklist: [ChecklistItem] {
        get { ChecklistCoding.decode(checklistJSON) }
        set { checklistJSON = ChecklistCoding.encode(newValue) }
    }
}
