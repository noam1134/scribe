import Foundation
import Testing
@testable import ScribeCore

/// Guards against the identifiers in code drifting from the entitlements files.
struct ScribeIDsTests {
    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent() // ScribeCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Core
        .deletingLastPathComponent() // repo root

    static func entitlements(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appending(path: relativePath))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test(arguments: [
        "App/Scribe-iOS.entitlements",
        "App/Scribe-macOS.entitlements",
        "Widgets/ScribeWidgets-iOS.entitlements",
        "Widgets/ScribeWidgets-macOS.entitlements",
    ])
    func appGroupMatchesEntitlements(path: String) throws {
        let groups = try Self.entitlements(path)["com.apple.security.application-groups"] as? [String]
        #expect(groups == [ScribeIDs.appGroup])
    }

    @Test(arguments: ["App/Scribe-iOS.entitlements", "App/Scribe-macOS.entitlements"])
    func cloudKitContainerMatchesEntitlements(path: String) throws {
        let containers = try Self.entitlements(path)["com.apple.developer.icloud-container-identifiers"] as? [String]
        #expect(containers == [ScribeIDs.cloudKitContainer])
    }
}
