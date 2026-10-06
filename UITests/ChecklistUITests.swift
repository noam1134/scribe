import XCTest

/// A task's checklist: steps are added in the inline editor and the row
/// shows the progress.
@MainActor
final class ChecklistUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    /// Waits for the focus to be on `element`.
    private func waitForFocus(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate { _, _ in (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed
    }

    func testStepsAddedInTheEditorShowTheirProgressOnTheRow() {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Pack bags #errands")
        app.buttons["newCategoryChip"].tap()
        app.buttons["Add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        app.staticTexts["Pack bags"].tap()
        let addStep = app.buttons["addStep"]
        XCTAssertTrue(addStep.waitForExistence(timeout: 5))
        addStep.tap()
        let steps = app.textFields.matching(identifier: "stepField")
        XCTAssertTrue(waitForFocus(steps.element(boundBy: 0)), "a new step takes the caret")
        steps.element(boundBy: 0).typeText("Boots\n")
        XCTAssertTrue(waitForFocus(steps.element(boundBy: 1)), "Return adds the next step and moves there")
        steps.element(boundBy: 1).typeText("Gloves")

        app.buttons["stepCheckbox-Boots"].tap()
        XCTAssertEqual(app.buttons["stepCheckbox-Boots"].label, "Mark step not done")

        let title = app.textFields["titleField"]
        title.tap()
        title.typeText("\n")
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Return in the title closes the editor")

        // The row shows "☑ 1/2"; VoiceOver reads it in words.
        let progress = app.descendants(matching: .any)["checklistProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "1 of 2 steps done")

        // Both steps were saved: they are there when the editor opens again.
        app.staticTexts["Pack bags"].tap()
        XCTAssertTrue(steps.element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertEqual(steps.element(boundBy: 0).value as? String, "Boots")
        XCTAssertEqual(steps.element(boundBy: 1).value as? String, "Gloves")
    }
}
