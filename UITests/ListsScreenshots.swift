import XCTest

/// Walks the Lists screen through its states on the demo data and saves a
/// screenshot of each, for reviewing the design. Opt-in:
///
///     TEST_RUNNER_SCRIBE_SCREENSHOTS=/some/folder xcodebuild … test \
///       -only-testing:ScribeUITests/ListsScreenshots
///
/// The PNGs are written to the folder and attached to the test result.
@MainActor
final class ListsScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!

    override func setUp() async throws {
        let path = ProcessInfo.processInfo.environment["SCRIBE_SCREENSHOTS"] ?? ""
        try XCTSkipIf(path.isEmpty, "Set TEST_RUNNER_SCRIBE_SCREENSHOTS to a folder to take screenshots")
        folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoData"]
        app.launch()
        XCTAssertTrue(app.buttons["section-Work"].waitForExistence(timeout: 5))
    }

    func testWalkThrough() throws {
        shoot("01-lists")

        app.buttons["section-Work"].tap()
        app.buttons["section-Thailand"].tap()
        shoot("02-collapsed")

        app.buttons["More"].tap()
        app.buttons["Show Completed"].tap()
        shoot("03-show-completed")
        app.buttons["More"].tap()
        app.buttons["Show Completed"].tap()
        app.buttons["section-Work"].tap()
        app.buttons["section-Thailand"].tap()

        app.staticTexts["Book flights to Bangkok"].tap()
        XCTAssertTrue(app.textFields["titleField"].waitForExistence(timeout: 5))
        shoot("04-inline-editor")
        app.textFields["titleField"].tap()
        app.textFields["titleField"].typeText("\n")

        app.buttons["section-Thailand"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        shoot("05-header-long-press")
        app.buttons["Rename"].tap()
        XCTAssertTrue(app.textFields["categoryNameField"].waitForExistence(timeout: 5))
        shoot("06-rename-inline")
        app.buttons["Cancel"].tap()

        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["category-Work"].waitForExistence(timeout: 5))
        shoot("07-edit-mode")
        app.buttons["Done"].tap()

        app.buttons["addTo-Thailand"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        shoot("08-composer-empty")
        field.typeText("Night train to Chiang Mai fri 8pm")
        shoot("09-composer")
        let notes = app.descendants(matching: .any)["quickAddNotes"].firstMatch
        notes.tap()
        notes.typeText("Sleeper, lower berth\nBook at the station")
        sleep(1)
        shoot("10-composer-notes")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        shoot("11-composer-keyboard-closed")
    }

    private func shoot(_ name: String) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
