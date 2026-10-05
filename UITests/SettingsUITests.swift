import XCTest

/// Settings on the iPhone (spec §16 Phase 6). The iPhone screens get their
/// Settings button at merge time, so these launch with `-settingsButton`,
/// which puts the real button over the app (Debug, `-uiTesting` only), and
/// tap it as a user would. `-demoSync` / `-demoPermission` set the iCloud
/// and permission states (there is no iCloud in a UI-test run). The
/// notification settings are pinned by launch arguments, so a switch
/// flipped here never carries over to the next run.
@MainActor
final class SettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-settingsButton",
            "-notifications.enabled", "YES",
            "-notifications.morningSummary", "YES",
            "-notifications.morningSummaryMinute", "540",
        ] + extra
        app.launch()
    }

    private func openSettings() {
        let button = app.buttons["settingsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// Taps the switch itself (a tap on the row's label doesn't flip it).
    private func flip(_ identifier: String) {
        let row = app.switches[identifier]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let control = row.switches.firstMatch
        (control.exists ? control : row).tap()
    }

    private func isOn(_ identifier: String) -> Bool {
        (app.switches[identifier].value as? String) == "1"
    }

    func testButtonOpensSettingsAndItsSwitchesWork() {
        launch()
        openSettings()

        XCTAssertEqual(app.staticTexts["syncHeadline"].label, "Sync off — sign in to iCloud")
        XCTAssertTrue(app.staticTexts["syncDetail"].label.hasPrefix("Open Settings, sign in with your Apple Account"))

        XCTAssertTrue(isOn("notificationsToggle"))
        XCTAssertTrue(isOn("morningSummaryToggle"))
        let time = app.datePickers["summaryTimePicker"]
        XCTAssertTrue(time.exists)

        flip("morningSummaryToggle")
        XCTAssertTrue(time.waitForNonExistence(timeout: 3), "no time to pick without a summary")
        flip("morningSummaryToggle")
        XCTAssertTrue(time.waitForExistence(timeout: 3))

        flip("notificationsToggle")
        XCTAssertFalse(isOn("notificationsToggle"))
        XCTAssertFalse(app.switches["morningSummaryToggle"].isEnabled, "the summary follows the master switch")
        XCTAssertFalse(time.exists)
        flip("notificationsToggle")
        XCTAssertTrue(app.switches["morningSummaryToggle"].isEnabled)

        XCTAssertTrue(app.buttons["exportButton"].exists)
        let version = app.descendants(matching: .any)["versionRow"]
        if !version.exists { app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 3))

        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Upcoming"].exists, "back in the app")
    }

    func testSyncProblemAndBlockedNotificationsAreExplained() {
        launch(["-demoSync", "offline", "-demoPermission", "denied"])
        openSettings()

        XCTAssertEqual(app.staticTexts["syncHeadline"].label, "Syncing with iCloud")
        XCTAssertTrue(app.staticTexts["lastSynced"].label.hasPrefix("Last synced "))
        XCTAssertTrue(app.staticTexts["syncProblem"].label.hasPrefix("Offline — changes are saved on this iPhone"))

        XCTAssertTrue(app.staticTexts["permissionProblem"].exists)
        XCTAssertTrue(app.buttons["openNotificationSettings"].exists)
        flip("notificationsToggle")
        XCTAssertTrue(app.buttons["openNotificationSettings"].waitForNonExistence(timeout: 3), "nothing to fix while notifications are off here")
    }

    func testSignedInShowsWhenItLastSynced() {
        launch(["-demoSync", "signedIn"])
        openSettings()
        XCTAssertEqual(app.staticTexts["syncHeadline"].label, "Syncing with iCloud")
        XCTAssertTrue(app.staticTexts["lastSynced"].label.hasPrefix("Last synced at "))
        XCTAssertFalse(app.staticTexts["syncProblem"].exists)
    }

    func testExportOpensTheShareSheet() {
        launch()
        openSettings()
        app.buttons["exportButton"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the share sheet should open with the file")
        XCTAssertFalse(app.alerts.firstMatch.exists, "no export error")
    }
}
