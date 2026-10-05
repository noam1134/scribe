import Foundation
import Testing
@testable import ScribeCore

struct DeepLinkTests {
    @Test func roundTrips() {
        let id = UUID()
        for link in [DeepLink.add(categoryID: nil), .add(categoryID: id), .item(id), .upcoming] {
            #expect(DeepLink(url: link.url) == link)
        }
        #expect(DeepLink.item(id).url.absoluteString == "scribe://item/\(id.uuidString)")
        #expect(DeepLink.add(categoryID: id).url.absoluteString == "scribe://add?category=\(id.uuidString)")
    }

    @Test(arguments: ["https://item/x", "scribe://item/not-a-uuid", "scribe://item", "scribe://settings", "scribe:"])
    func rejectsUnknownURLs(text: String) throws {
        #expect(DeepLink(url: try #require(URL(string: text))) == nil)
    }

    @Test func addIgnoresAMalformedCategory() throws {
        #expect(DeepLink(url: try #require(URL(string: "scribe://add?category=zzz"))) == .add(categoryID: nil))
    }
}
