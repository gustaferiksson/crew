import XCTest

final class ChatDraftUITests: XCTestCase {
    @MainActor func testDraftSurvivesLeavingTheChatAndShowsInTheRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "sidebar", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let row = app.staticTexts["Tuesday's standup notes are filed."]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Move standup to 10")
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
        app.navigationBars.buttons["BackButton"].tap()

        let draftLine = app.staticTexts["Draft: Move standup to 10"]
        XCTAssertTrue(draftLine.waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)

        draftLine.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Move standup to 10")
        app.buttons["Send"].tap()
        XCTAssertNotEqual(composer.value as? String, "Move standup to 10")
        app.navigationBars.buttons["BackButton"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(draftLine.exists)
    }
}
