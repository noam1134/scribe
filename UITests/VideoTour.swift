import XCTest

/// The showcase video's iPhone scenes, played at a watchable pace on the
/// `-videoDemo` lists while the simulator is recorded. Opt-in: set
/// `TEST_RUNNER_SCRIBE_VIDEO=1`. Prints `VIDEO_MARK <scene> <time>` lines to
/// cut the recording by.
@MainActor
final class VideoTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try XCTSkipIf((ProcessInfo.processInfo.environment["SCRIBE_VIDEO"] ?? "").isEmpty, "Set TEST_RUNNER_SCRIBE_VIDEO=1 to play the video tour")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-videoDemo"]
    }

    func testTour() throws {
        app.launch()
        XCTAssertTrue(app.buttons["section-Thailand"].waitForExistence(timeout: 10))
        pause(2)

        mark("smartadd")
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        pause(0.8)
        typeSlowly(field, "remind me to book the airport taxi in Thailand tomorrow 9am")
        pause(2.2)
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Book the airport taxi"].waitForExistence(timeout: 5))
        pause(2.5)

        mark("sections")
        let work = app.buttons["section-Work"]
        let borovets = app.buttons["section-Borovets"]
        work.tap()
        pause(1.2)
        borovets.tap()
        pause(1.2)
        borovets.tap()
        pause(1.2)
        work.tap()
        pause(1.5)
        app.buttons["checkbox-Hotel in Chiang Mai"].tap()
        pause(2.5)

        mark("checklist")
        app.staticTexts["Pack for Borovets"].tap()
        pause(1.5)
        let steps = app.buttons.matching(identifier: "Mark step done")
        steps.element(boundBy: 0).tap()
        pause(0.9)
        app.buttons.matching(identifier: "Mark step done").element(boundBy: 0).tap()
        pause(1.5)
        let title = app.textFields["titleField"]
        let window = app.windows.firstMatch.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.width - 40, dy: title.frame.midY))
            .tap()
        pause(2.5)

        mark("upcoming")
        app.tabBars.buttons["Upcoming"].tap()
        pause(3)
        app.tabBars.buttons["Lists"].tap()
        pause(1.5)
        mark("end")
    }

    /// Claude's "Book hotel in Avoriaz" reaching Scribe: connected off
    /// camera, then Scribe opened from the home screen once the pretend
    /// mailbox hands the item out (25 s after launch).
    func testClaudeArrival() throws {
        app.launchArguments = ["-uiTesting", "-videoDemo", "-demoMailboxItem"]
        app.launch()
        let launched = Date()
        let settings = app.navigationBars["Lists"].buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let field = app.textFields["claudeLinkField"]
        for _ in 0..<4 where !(field.exists && field.isHittable) { app.swipeUp() }
        field.tap()
        field.typeText("https://scribe-mailbox.example.workers.dev/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/mcp\n")
        XCTAssertTrue(app.staticTexts["claudeStatus"].waitForExistence(timeout: 10))
        app.buttons["closeSettings"].tap()
        pause(1)
        XCUIDevice.shared.press(.home)
        let wait = 27 - Date().timeIntervalSince(launched)
        if wait > 0 { pause(wait) }
        mark("arrival")
        pause(1.5)
        app.activate()
        XCTAssertTrue(app.staticTexts["Book hotel in Avoriaz"].waitForExistence(timeout: 10))
        pause(3)
        mark("end")
    }

    private func typeSlowly(_ field: XCUIElement, _ text: String) {
        for character in text {
            field.typeText(String(character))
            Thread.sleep(forTimeInterval: 0.04)
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func mark(_ scene: String) {
        print("VIDEO_MARK \(scene) \(Date().timeIntervalSince1970)")
    }
}
