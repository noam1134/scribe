#if DEBUG
import Foundation
import ScribeCore

/// UI-test runs (`-uiTesting`) never reach the network: a pretend mailbox
/// that accepts every snapshot. `-demoMailboxItem` queues one item Claude
/// "added" — "Book flights" for a new "Trips" category — handed out until
/// it's acknowledged. With `-videoDemo` it is the showcase video's
/// "Book hotel in Avoriaz", held back for 25 s so the video can show it
/// arriving when Scribe comes to the front. Debug builds only.
@MainActor
enum MailboxDemo {
    static var transport: (any MailboxTransport)? {
        guard SharedStore.isUITesting else { return nil }
        guard CommandLine.arguments.contains("-demoMailboxItem") else { return DemoMailboxTransport(items: []) }
        if DemoData.isVideoRequested {
            return DemoMailboxTransport(
                items: [MailboxItem(id: "demo-video", title: "Book hotel in Avoriaz", category: "Avoriaz", createCategory: true)],
                availableAt: Date().addingTimeInterval(25)
            )
        }
        return DemoMailboxTransport(items: [MailboxItem(id: "demo-1", title: "Book flights", category: "Trips", createCategory: true)])
    }
}

actor DemoMailboxTransport: MailboxTransport {
    private var items: [MailboxItem]
    private let availableAt: Date

    init(items: [MailboxItem], availableAt: Date = .distantPast) {
        self.items = items
        self.availableAt = availableAt
    }

    func inbox(_ connection: MailboxConnection) async throws -> [MailboxItem] {
        Date() >= availableAt ? items : []
    }

    func acknowledge(_ ids: [String], _ connection: MailboxConnection) async throws {
        items.removeAll { ids.contains($0.id) }
    }

    func publish(_ snapshot: MailboxSnapshot, _ connection: MailboxConnection) async throws {}
}
#endif
