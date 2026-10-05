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

    /// Adds through the composer, filed into an "errands" category that the
    /// first call creates — the composer needs a category (spec §19).
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

    func testLaunchShowsTheTabs() {
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Lists"].isSelected, "the app opens on Lists")
        XCTAssertTrue(app.tabBars.buttons["Upcoming"].exists)
        XCTAssertTrue(app.navigationBars["Lists"].exists)
    }

    func testComposerNeedsATitleAndACategory() {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add"].isEnabled)
        field.typeText("Buy milk tomorrow")
        XCTAssertFalse(app.buttons["Add"].isEnabled, "no category picked yet")
        XCTAssertTrue(app.staticTexts["categoryHint"].exists)
        field.typeText(" #errands")
        app.buttons["newCategoryChip"].tap()
        XCTAssertTrue(app.buttons["Add"].isEnabled)
        app.buttons["Add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
    }

    func testQuickAddShowsTheItemInUpcoming() {
        quickAdd("Buy milk tomorrow")
        app.tabBars.buttons["Upcoming"].tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
    }

    func testCompletingATaskRemovesItFromUpcoming() {
        quickAdd("Call Dan today")
        app.tabBars.buttons["Upcoming"].tap()
        let checkbox = app.buttons["checkbox-Call Dan"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.tap()
        XCTAssertTrue(app.staticTexts["Call Dan"].waitForNonExistence(timeout: 5))
    }

    /// On Upcoming the date change moves the row to another day.
    func testEditedTitleSurvivesADateChange() {
        quickAdd("Pay rent today")
        app.tabBars.buttons["Upcoming"].tap()
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

    func testDeleteThenUndoInLists() {
        quickAdd("Water plants")
        XCTAssertFalse(app.buttons["section-Inbox"].exists, "the Inbox only shows when something is in it")
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

    /// The widget's "+" (spec §8, §10.1) opens the composer through this link.
    func testAddLinkOpensTheComposer() {
        XCTAssertTrue(app.tabBars.buttons["Upcoming"].waitForExistence(timeout: 5))
        app.open(URL(string: "scribe://add")!)
        XCTAssertTrue(app.textFields["quickAddField"].waitForExistence(timeout: 5))
    }

    func testDuplicateCategoryNameIsExplainedInline() {
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

    // MARK: Lists (spec §20)

    private func addCategory(_ name: String) {
        app.buttons["Add Category"].tap()
        let field = app.textFields["newCategoryField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(name + "\n")
        XCTAssertTrue(app.buttons["section-\(name)"].waitForExistence(timeout: 5))
    }

    /// Demo data: Inbox, Work, Thailand and בית, with two items whose
    /// links are fixed (`DemoData`).
    private func relaunchWithDemoData() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-demoData"]
        app.launch()
        XCTAssertTrue(app.buttons["section-Work"].waitForExistence(timeout: 5))
    }

    /// Collapses Thailand, which sits below Work's rows: Work closes for
    /// the tap and opens again.
    private func collapseThailand() -> XCUIElement {
        let work = app.buttons["section-Work"]
        let thailand = app.buttons["section-Thailand"]
        work.tap()
        thailand.tap()
        work.tap()
        XCTAssertEqual(thailand.value as? String, "Collapsed")
        XCTAssertEqual(work.value as? String, "Expanded")
        return thailand
    }

    func testSectionCollapsesAndExpands() {
        quickAdd("Water plants")
        let row = app.staticTexts["Water plants"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let header = app.buttons["section-errands"]
        XCTAssertEqual(header.value as? String, "Expanded")
        header.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertEqual(header.value as? String, "Collapsed")
        header.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testSectionPlusPreselectsItsCategory() {
        addCategory("Work")
        XCTAssertTrue(app.buttons["addFirst-Work"].exists)
        let header = app.buttons["section-Work"]
        header.tap()
        XCTAssertEqual(header.value as? String, "Collapsed")
        app.buttons["addTo-Work"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pickCategory-Work"].isSelected)
        field.typeText("Draft the plan")
        XCTAssertTrue(app.buttons["Add"].isEnabled)
        app.buttons["Add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Draft the plan"].waitForExistence(timeout: 5), "adding through + opens the section")
        XCTAssertEqual(header.value as? String, "Expanded")
        XCTAssertFalse(app.buttons["addFirst-Work"].exists)
    }

    func testEmptyCategoryOffersItsFirstItem() {
        addCategory("Garden")
        app.buttons["addFirst-Garden"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pickCategory-Garden"].isSelected)
        field.typeText("Plant tomatoes\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Plant tomatoes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addFirst-Garden"].exists)
    }

    func testShowCompletedRevealsDoneItems() {
        quickAdd("Call Dan")
        let checkbox = app.buttons["checkbox-Call Dan"]
        checkbox.tap()
        let row = app.staticTexts["Call Dan"]
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "done items are hidden by default")
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "completing a hidden item offers Undo")
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        checkbox.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        app.buttons["More"].tap()
        app.buttons["Show Completed"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testEditShowsOnlyTheCategories() {
        quickAdd("Water plants")
        XCTAssertTrue(app.staticTexts["Water plants"].waitForExistence(timeout: 5))
        app.buttons["Edit"].tap()
        let category = app.buttons["category-errands"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Water plants"].exists)
        category.tap()
        let name = app.textFields["categoryNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" run\n")
        XCTAssertTrue(app.buttons["category-errands run"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Water plants"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["section-errands run"].exists)
    }

    func testHeaderLongPressRenamesAndDeletes() {
        quickAdd("Water plants")
        app.buttons["section-errands"].press(forDuration: 1)
        let rename = app.buttons["Rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let name = app.textFields["categoryNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" run\n")
        let header = app.buttons["section-errands run"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))

        header.press(forDuration: 1)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.buttons["section-Inbox"].waitForExistence(timeout: 5), "its items move to the Inbox")
        XCTAssertFalse(header.exists)
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["section-Inbox"].waitForNonExistence(timeout: 5))
    }

    /// Notifications and widgets open items with this link (spec §8, §20).
    func testItemLinkOpensTheItemInItsCollapsedSection() {
        relaunchWithDemoData()
        let header = collapseThailand() // its item is now a scroll away
        app.tabBars.buttons["Upcoming"].tap()
        app.open(URL(string: "scribe://item/5C1B0E00-0000-4000-8000-000000000001")!)
        let title = app.textFields["titleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Passport number")
        XCTAssertTrue(title.isHittable, "scrolled into view")
        XCTAssertTrue(app.tabBars.buttons["Lists"].isSelected)
        XCTAssertEqual(header.value as? String, "Expanded")
    }

    /// Show Completed stays off: the done item shows while its editor is open.
    func testLinkToADoneItemShowsItWhileItsEditorIsOpen() {
        relaunchWithDemoData()
        app.open(URL(string: "scribe://item/5C1B0E00-0000-4000-8000-000000000002")!)
        let title = app.textFields["titleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Renew gym membership")
        XCTAssertTrue(title.isHittable, "scrolled into view")
        title.tap()
        title.typeText("\n")
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Renew gym membership"].exists)
    }

    /// The editor's category chip moves the row into a collapsed section,
    /// which opens to show it.
    func testMovingTheEditedItemOpensItsNewSection() {
        relaunchWithDemoData()
        let thailand = collapseThailand()
        app.staticTexts["Send the quarterly report"].tap()
        let chip = app.buttons["categoryChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        let destination = app.buttons["\u{1F1F9}\u{1F1ED} Thailand"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        XCTAssertEqual(thailand.value as? String, "Expanded")
        XCTAssertTrue(app.textFields["titleField"].waitForExistence(timeout: 5), "the editor stays open")
    }

    // MARK: Keyboard and notes (spec §20)

    private func hasFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// Waits for the focus to be (or stop being) on `element`.
    private func waitForFocus(_ element: XCUIElement, _ focused: Bool = true) -> Bool {
        let predicate = NSPredicate { _, _ in self.hasFocus(element) == focused }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed
    }

    /// Halfway between `element` and the keyboard (or the bottom of the
    /// screen when the simulator shows none): list background on a short list.
    private func emptySpace(below element: XCUIElement) -> XCUICoordinate {
        let keyboard = app.keyboards.firstMatch
        let bottom = keyboard.exists ? keyboard.frame.minY : app.frame.maxY
        let y = (element.frame.maxY + bottom) / 2
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: y))
    }

    func testTappingOutsideAFieldClosesTheKeyboard() {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(field))

        // Another field takes the focus with one tap.
        let notes = app.descendants(matching: .any)["quickAddNotes"].firstMatch
        notes.tap()
        XCTAssertTrue(waitForFocus(notes))
        notes.typeText("charger")
        XCTAssertEqual(notes.value as? String, "charger")

        // A tap on something that isn't a field closes the keyboard.
        app.staticTexts["Try \u{201C}call mom tomorrow 9am #family\u{201D}"].tap()
        XCTAssertTrue(waitForFocus(notes, false))

        // Chips work on the first tap.
        field.tap()
        XCTAssertTrue(waitForFocus(field))
        field.typeText("Pack bags #errands")
        // The composer's own controls keep the caret, so Return still saves.
        app.buttons["kindToggle"].tap()
        XCTAssertTrue(hasFocus(field), "the kind toggle keeps the keyboard")
        XCTAssertEqual(app.buttons["kindToggle"].label, "Memo")
        app.buttons["kindToggle"].tap()
        app.buttons["newCategoryChip"].tap()
        XCTAssertTrue(app.buttons["Add"].isEnabled, "the chip should work on the first tap")
        XCTAssertTrue(hasFocus(field), "a category chip keeps the keyboard")
        field.typeText("\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Return saves")

        // In Lists, empty space closes the inline editor's keyboard and
        // leaves the editor open.
        app.staticTexts["Pack bags"].tap()
        let title = app.textFields["titleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        XCTAssertTrue(waitForFocus(title))
        emptySpace(below: app.buttons["kindChip"]).tap()
        XCTAssertTrue(waitForFocus(title, false))
        XCTAssertTrue(title.exists)
    }

    func testComposerSavesNotes() {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Pack bags #errands")
        app.buttons["newCategoryChip"].tap()
        let notes = app.descendants(matching: .any)["quickAddNotes"].firstMatch
        notes.tap()
        notes.typeText("Passport\nCharger")
        app.buttons["Add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        app.staticTexts["Pack bags"].tap()
        let saved = app.descendants(matching: .any)["notesField"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.value as? String, "Passport\nCharger")
    }

    /// The tap that closes the keyboard must not take Paste's tap away.
    func testPasteIntoNotes() {
        UIPasteboard.general.string = "Gate 4"
        app.buttons["quickAddBar"].tap()
        let notes = app.descendants(matching: .any)["quickAddNotes"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        XCTAssertTrue(waitForFocus(notes))
        notes.press(forDuration: 1)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        XCTAssertEqual(notes.value as? String, "Gate 4")
        XCTAssertTrue(hasFocus(notes), "the field keeps the focus")
    }
}
