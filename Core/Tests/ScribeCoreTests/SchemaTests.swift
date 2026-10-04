import SwiftData
import Testing
@testable import ScribeCore

struct SchemaTests {
    /// Record type names in CloudKit come from these entity names.
    /// Renaming a model after launch breaks sync — this test makes it loud.
    @Test func entityNamesArePinned() {
        #expect(Set(StoreFactory.schema.entities.map(\.name)) == ["Item", "Category"])
    }

    @Test func modelsFollowCloudKitRules() {
        for entity in StoreFactory.schema.entities {
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) must not be unique")
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name) needs a default value or must be optional")
            }
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) must be optional")
            }
        }
    }

    @Test func itemDueRoundTripsThroughStoredFields() {
        let item = Item(title: "x", due: DueDate(day: LocalDay(2026, 10, 12), minute: 540))
        #expect(item.dueDay == "2026-10-12")
        #expect(item.dueMinute == 540)
        #expect(item.due == DueDate(day: LocalDay(2026, 10, 12), minute: 540))
        item.due = nil
        #expect(item.dueDay == nil && item.dueMinute == nil)
    }

    @Test func corruptStoredValuesDegradeSafely() {
        let item = Item(title: "x")
        item.kindRaw = "something-new"
        item.dueDay = "not-a-day"
        #expect(item.kind == .task)
        #expect(item.due == nil)
        item.dueDay = "2026-10-12"
        item.dueMinute = 5000
        #expect(item.due == DueDate(day: LocalDay(2026, 10, 12)))
    }
}
