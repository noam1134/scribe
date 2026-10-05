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

    func testLaunchShowsTheTabs() {
        XCTAssertTrue(app.tabBars.buttons["Upcoming"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Categories"].exists)
    }
}
