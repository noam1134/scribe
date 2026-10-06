import Foundation
import Testing
@testable import ScribeCore

/// A made-up key for the tests.
private let key = "3f9a0c1d2e4b5a6978877665544332211aabbccddeeff00112233445566778899"

/// The connector link the user pastes into Settings › Claude, and the
/// requests built from it.
struct MailboxConnectionTests {
    let link = "https://scribe-mailbox.noam.workers.dev/\(key)/mcp"

    @Test func readsTheConnectorLink() throws {
        let connection = try #require(MailboxConnection(link: link))
        #expect(connection.baseURL.absoluteString == "https://scribe-mailbox.noam.workers.dev")
        #expect(connection.key == key)
        #expect(connection.host == "scribe-mailbox.noam.workers.dev")
        #expect(connection.link == link)
        #expect(connection.url(.snapshot).absoluteString == "https://scribe-mailbox.noam.workers.dev/\(key)/app/snapshot")
        #expect(connection.url(.inbox).absoluteString == "https://scribe-mailbox.noam.workers.dev/\(key)/app/inbox")
        #expect(connection.url(.ack).absoluteString == "https://scribe-mailbox.noam.workers.dev/\(key)/app/inbox/ack")
    }

    @Test(arguments: [
        "  https://scribe-mailbox.noam.workers.dev/\(key)/mcp\n",
        "https://scribe-mailbox.noam.workers.dev/\(key)/mcp/",
        "https://scribe-mailbox.noam.workers.dev/\(key)",
        "https://scribe-mailbox.noam.workers.dev/\(key)/",
        "HTTPS://scribe-mailbox.noam.workers.dev/\(key)/mcp",
    ])
    func toleratesHowALinkIsCopied(text: String) throws {
        let connection = try #require(MailboxConnection(link: text))
        #expect(connection.link == link)
    }

    @Test func aLocalWorkerMayUseHTTPAndAPort() throws {
        let connection = try #require(MailboxConnection(link: "http://localhost:8787/\(key)/mcp"))
        #expect(connection.url(.inbox).absoluteString == "http://localhost:8787/\(key)/app/inbox")
    }

    @Test(arguments: [
        "",
        "scribe-mailbox.noam.workers.dev/\(key)/mcp",
        "http://scribe-mailbox.noam.workers.dev/\(key)/mcp",
        "https://scribe-mailbox.noam.workers.dev/mcp",
        "https://scribe-mailbox.noam.workers.dev/",
        "https://scribe-mailbox.noam.workers.dev/tooshort/mcp",
        "https://scribe-mailbox.noam.workers.dev/\(key)/app/inbox",
        "https://scribe-mailbox.noam.workers.dev/extra/\(key)/mcp",
        "https://scribe-mailbox.noam.workers.dev/\(key)/mcp?x=1",
        "https://scribe-mailbox.noam.workers.dev/\(key)/mcp#x",
        "https://user:pw@scribe-mailbox.noam.workers.dev/\(key)/mcp",
        "https://scribe-mailbox.noam.workers.dev/\(String(key.dropLast()))!/mcp",
        "ftp://scribe-mailbox.noam.workers.dev/\(key)/mcp",
        "not a link",
    ])
    func refusesWhatIsntAMailboxLink(text: String) {
        #expect(MailboxConnection(link: text) == nil)
    }

    // MARK: Requests

    @Test func publishingPutsTheSnapshotAsJSON() throws {
        let connection = try #require(MailboxConnection(link: link))
        let snapshot = MailboxSnapshot(updatedAt: Date(timeIntervalSince1970: 0), timeZone: "UTC", categories: [.init(name: "Work", emoji: "")], upcoming: [])
        let request = try MailboxRequests.publish(snapshot, to: connection)
        #expect(request.httpMethod == "PUT")
        #expect(request.url == connection.url(.snapshot))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == MailboxRequests.timeout)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(MailboxSnapshot.self, from: try #require(request.httpBody)) == snapshot)
    }

    @Test func inboxAndAcknowledgement() throws {
        let connection = try #require(MailboxConnection(link: link))
        let inbox = MailboxRequests.inbox(connection)
        #expect(inbox.httpMethod == "GET")
        #expect(inbox.url == connection.url(.inbox))
        #expect(inbox.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)

        let ack = try MailboxRequests.acknowledge(["a", "b"], to: connection)
        #expect(ack.httpMethod == "POST")
        #expect(ack.url == connection.url(.ack))
        #expect(String(decoding: try #require(ack.httpBody), as: UTF8.self) == #"{"ids":["a","b"]}"#)
    }

    @Test func statusCodes() {
        #expect(throws: Never.self) { try MailboxRequests.check(status: 200) }
        #expect(throws: Never.self) { try MailboxRequests.check(status: 204) }
        #expect(throws: MailboxFailure.linkRejected) { try MailboxRequests.check(status: 404) }
        #expect(throws: MailboxFailure.server(500)) { try MailboxRequests.check(status: 500) }
        #expect(throws: MailboxFailure.server(400)) { try MailboxRequests.check(status: 400) }
    }

    @Test func failuresFromErrors() {
        #expect(MailboxFailure(URLError(.notConnectedToInternet)) == .offline)
        #expect(MailboxFailure(URLError(.timedOut)) == .offline)
        #expect(MailboxFailure(MailboxFailure.linkRejected) == .linkRejected)
        struct Other: Error {}
        #expect(MailboxFailure(Other()) == .server(0))
    }

    @Test func readsTheInboxLeniently() throws {
        let json = #"""
        {"items":[
          {"id":"1","createdAt":"2026-10-06T13:49:21.248Z","title":"Book flights","category":"Thailand","createCategory":false,"kind":"task","dueDate":"2026-10-09","dueTime":"09:00","notes":"window"},
          {"id":"2","title":"Passport","category":"Thailand","kind":"note","extra":true}
        ]}
        """#
        let items = try MailboxRequests.decodeInbox(Data(json.utf8))
        #expect(items == [
            MailboxItem(id: "1", title: "Book flights", category: "Thailand", dueDate: "2026-10-09", dueTime: "09:00", notes: "window"),
            MailboxItem(id: "2", title: "Passport", category: "Thailand", kind: .task),
        ])
    }

    @Test func anInboxWithoutIDsIsUnreadable() {
        #expect(throws: MailboxFailure.unreadable) { try MailboxRequests.decodeInbox(Data(#"{"items":[{"title":"x"}]}"#.utf8)) }
        #expect(throws: MailboxFailure.unreadable) { try MailboxRequests.decodeInbox(Data("<html>".utf8)) }
    }
}
