import XCTest

/// Plain-language quick-add on the iPhone: a category named in the text is
/// pre-picked as you type and the request words leave the title. The
/// on-device model is off in UI tests, so this is the parser's layer alone.
@MainActor
final class SmartAddUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testAMentionedCategoryIsPrePickedAndTheTitleCleaned() {
        app.buttons["Add Category"].tap()
        let name = app.textFields["newCategoryField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Work\n")
        XCTAssertTrue(app.buttons["section-Work"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addFirst-Work"].exists)

        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let work = app.buttons["pickCategory-Work"]
        field.typeText("remind me to call the bank")
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        XCTAssertFalse(work.isSelected)
        XCTAssertFalse(app.buttons["Add"].isEnabled, "nothing picks a category yet")

        field.typeText(" for work")
        waitUntil(work, "isSelected == true")
        XCTAssertEqual(work.value as? String, "Suggested", "marked as worked out, not chosen")
        XCTAssertTrue(app.buttons["Add"].isEnabled)

        app.buttons["Add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
        XCTAssertTrue(app.staticTexts["Call the bank"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addFirst-Work"].exists, "filed in Work")
    }

    private func waitUntil(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5) {
        let condition = expectation(for: NSPredicate(format: format), evaluatedWith: element)
        wait(for: [condition], timeout: timeout)
    }
}
