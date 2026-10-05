import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct UndoCenterTests {
    @Test func undoRunsOnceAndClears() throws {
        let center = UndoCenter()
        var undone = 0
        center.offer("Deleted") { undone += 1 }
        #expect(center.current?.message == "Deleted")
        try center.performUndo()
        try center.performUndo()
        #expect(undone == 1)
        #expect(center.current == nil)
    }

    @Test func newOfferReplacesOld() throws {
        let center = UndoCenter()
        var log: [String] = []
        center.offer("first") { log.append("first") }
        center.offer("second") { log.append("second") }
        try center.performUndo()
        #expect(log == ["second"])
    }

    @Test func offersExpire() async throws {
        let center = UndoCenter(duration: .milliseconds(50))
        center.offer("Deleted") {}
        try await Task.sleep(for: .milliseconds(300))
        #expect(center.current == nil)
    }
}
