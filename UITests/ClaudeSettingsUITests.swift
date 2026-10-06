import XCTest

/// Settings › Claude on the iPhone: pasting the connector link connects
/// Scribe to the Claude mailbox. UI-test runs use a pretend mailbox (no
/// network) and keep the link in memory, so every run starts unconnected.
@MainActor
final class ClaudeSettingsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let link = "https://scribe-mailbox.example.workers.dev/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/mcp"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
    }

    private func openSettings() {
        let lists = app.tabBars.buttons["Lists"]
        XCTAssertTrue(lists.waitForExistence(timeout: 5))
        lists.tap()
        let button = app.navigationBars["Lists"].buttons["settingsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// The Claude section sits below the fold on smaller phones.
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<4 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
    }

    private func paste(_ text: String) {
        let field = app.textFields["claudeLinkField"]
        reveal(field)
        field.tap()
        field.typeText(text + "\n")
    }

    func testALinkConnectsAndDisconnects() {
        launch()
        openSettings()

        paste("https://example.com/not-a-mailbox")
        XCTAssertTrue(app.staticTexts["claudeLinkProblem"].waitForExistence(timeout: 3), "a link without a key is refused")
        XCTAssertTrue(app.textFields["claudeLinkField"].exists, "still unconnected")

        let field = app.textFields["claudeLinkField"]
        // At the end of the text, to delete all of it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        XCTAssertEqual(field.value as? String, "https://…/mcp", "back to the placeholder")
        XCTAssertFalse(app.staticTexts["claudeLinkProblem"].exists, "editing clears the problem")
        field.typeText(link + "\n")

        let host = app.descendants(matching: .any)["claudeMailboxHost"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertTrue(host.label.contains("scribe-mailbox.example.workers.dev"), "shows the host, never the key: \(host.label)")
        let status = app.staticTexts["claudeStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let synced = NSPredicate(format: "label == 'Last synced just now'")
        wait(for: [expectation(for: synced, evaluatedWith: status)], timeout: 10)
        XCTAssertFalse(app.staticTexts["claudeProblem"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '0123456789abcdef'")).firstMatch.exists, "the key isn't shown")

        reveal(app.buttons["claudeSyncNow"])
        app.buttons["claudeSyncNow"].tap()
        wait(for: [expectation(for: synced, evaluatedWith: status)], timeout: 10)

        reveal(app.buttons["claudeDisconnect"])
        app.buttons["claudeDisconnect"].tap()
        XCTAssertTrue(app.textFields["claudeLinkField"].waitForExistence(timeout: 5))
        XCTAssertFalse(host.exists)
    }

    func testAnItemClaudeQueuedLandsInItsNewCategory() {
        launch(["-demoMailboxItem"])
        openSettings()
        paste(link)
        let status = app.staticTexts["claudeStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label == 'Last synced just now'"), evaluatedWith: status)], timeout: 10)

        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["section-Trips"].waitForExistence(timeout: 5), "the category Claude proposed")
        XCTAssertTrue(app.staticTexts["Book flights"].waitForExistence(timeout: 5), "the queued item is in it")
    }
}
