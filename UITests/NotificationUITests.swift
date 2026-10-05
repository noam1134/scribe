import XCTest

/// Real notifications on the simulator (spec §11): a due-time alert fires,
/// its Done button completes the task while the app is in the background,
/// and tapping an alert opens its item. Slow — it waits for the clock — so
/// it takes about four minutes. The first run answers the permission alert.
@MainActor
final class NotificationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-enableNotifications"]
        app.launch()
    }

    func testDueTimeAlertDoneButtonAndTap() {
        let suffix = String((0..<4).map { _ in "abcdefghjkmnpqrstuvwxyz".randomElement()! })
        let doneTitle = "Ping done \(suffix)"
        let openTitle = "Ping open \(suffix)"

        quickAdd("\(doneTitle) at \(clock(minutesFromNow: 2))")
        allowNotificationsIfAsked()
        quickAdd("\(openTitle) at \(clock(minutesFromNow: 3))")
        XCTAssertTrue(app.staticTexts[doneTitle].waitForExistence(timeout: 5))

        // Done from the expanded banner while Scribe is in the background.
        XCUIDevice.shared.press(.home)
        let doneBanner = banner(containing: doneTitle)
        XCTAssertTrue(doneBanner.waitForExistence(timeout: 200), "the first alert should fire within ~2 minutes")
        doneBanner.press(forDuration: 1.5)
        let doneButton = springboard.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        app.activate()
        XCTAssertTrue(app.staticTexts[openTitle].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[doneTitle].waitForNonExistence(timeout: 10), "Done should complete the task")

        // Tapping the next alert (shown over the open app) opens its item.
        let openBanner = banner(containing: openTitle)
        XCTAssertTrue(openBanner.waitForExistence(timeout: 120), "the second alert should fire a minute later")
        openBanner.tap()
        let title = app.textFields["titleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the item should open in its category")
        XCTAssertEqual(title.value as? String, openTitle)
    }

    // MARK: Helpers

    private func quickAdd(_ text: String) {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text + " #errands")
        let create = app.buttons["newCategoryChip"]
        if create.exists { create.tap() }
        app.buttons["Add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
    }

    /// "HH:MM" on the device clock. (Breaks if run in the minutes before midnight.)
    private func clock(minutesFromNow minutes: Int) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    /// The system asks once, when the first dated item exists.
    private func allowNotificationsIfAsked() {
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    private func banner(containing text: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
