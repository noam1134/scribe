import Foundation

/// Shape of Settings → Export as JSON. `version` bumps on breaking changes.
public struct ExportDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var categories: [ExportedCategory]
    public var items: [ExportedItem]
}

public struct ExportedCategory: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var colorName: String
    public var sortIndex: Double
}

public struct ExportedItem: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var kind: ItemKind
    public var categoryID: UUID?
    public var dueDay: String?
    public var dueMinute: Int?
    public var isDone: Bool
    public var doneAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    /// Always written (empty for none); optional so older exports still read.
    public var checklist: [ChecklistItem]?
}

extension ExportDocument {
    static let currentVersion = 1

    /// ISO-8601 with milliseconds, so `createdAt` ordering survives a round trip.
    static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return try Date(text, strategy: dateStyle)
        }
        return decoder
    }
}
