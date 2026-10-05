import XCTest

/// Smoke tests for the iPhone app (spec §15). The app launches with
/// `-uiTesting`: an in-memory store, no iCloud.
@MainActor
final class ScribeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func quickAdd(_ text: String) {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text + "\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
    }

    func testLaunchShowsTheTabs() {
        XCTAssertTrue(app.tabBars.buttons["Upcoming"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Categories"].exists)
    }

    func testComposerAddsOnlyWithATitle() {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add"].isEnabled)
        field.typeText("Buy milk tomorrow\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
    }

    func testQuickAddShowsTheItemInUpcoming() {
        quickAdd("Buy milk tomorrow")
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
    }

    func testCompletingATaskRemovesItFromUpcoming() {
        quickAdd("Call Dan today")
        let checkbox = app.buttons["checkbox-Call Dan"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.tap()
        XCTAssertTrue(app.staticTexts["Call Dan"].waitForNonExistence(timeout: 5))
    }

    func testEditedTitleSurvivesADateChange() {
        quickAdd("Pay rent today")
        app.staticTexts["Pay rent"].tap()
        let field = app.textFields["titleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" now")
        app.buttons["dateChip"].tap()
        app.buttons["Tomorrow"].tap()
        let moved = app.textFields["titleField"]
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        moved.tap()
        moved.typeText("\n")
        XCTAssertTrue(app.staticTexts["Pay rent now"].waitForExistence(timeout: 5))
    }

    func testDeleteThenUndoInTheInbox() {
        quickAdd("Water plants")
        app.tabBars.buttons["Categories"].tap()
        app.buttons["inboxRow"].tap()
        let row = app.staticTexts["Water plants"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testDuplicateCategoryNameIsExplainedInline() {
        app.tabBars.buttons["Categories"].tap()
        for _ in 0..<2 {
            app.buttons["Add Category"].tap()
            let field = app.textFields["newCategoryField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText("Work\n")
        }
        let message = app.staticTexts["inlineError"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "There’s already a category with that name.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
