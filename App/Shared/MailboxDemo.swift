#if DEBUG
import Foundation
import ScribeCore

/// UI-test runs (`-uiTesting`) never reach the network: a pretend mailbox
/// that accepts every snapshot. `-demoMailboxItem` queues one item Claude
/// "added" — "Book flights" for a new "Trips" category — handed out until
/// it's acknowledged. Debug builds only.
@MainActor
enum MailboxDemo {
    static var transport: (any MailboxTransport)? {
        guard SharedStore.isUITesting else { return nil }
        let queued = CommandLine.arguments.contains("-demoMailboxItem")
            ? [MailboxItem(id: "demo-1", title: "Book flights", category: "Trips", createCategory: true)]
            : []
        return DemoMailboxTransport(items: queued)
    }
}

actor DemoMailboxTransport: MailboxTransport {
    private var items: [MailboxItem]

    init(items: [MailboxItem]) {
        self.items = items
    }

    func inbox(_ connection: MailboxConnection) async throws -> [MailboxItem] {
        items
    }

    func acknowledge(_ ids: [String], _ connection: MailboxConnection) async throws {
        items.removeAll { ids.contains($0.id) }
    }

    func publish(_ snapshot: MailboxSnapshot, _ connection: MailboxConnection) async throws {}
}
#endif
