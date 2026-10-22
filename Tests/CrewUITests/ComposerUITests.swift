import XCTest

final class ComposerUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"] + extra
        app.launch()
        return app
    }

    @MainActor private func type(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
        return field
    }

    @MainActor func testAMultiLineDraftKeepsTheFieldFullWidthAndSends() {
        let app = launch("composer-line")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let oneLine = field.frame
        _ = type(" and put the confirmation in the trip notes so Chef can plan the meals around the flight", in: app)
        XCTAssertGreaterThan(field.frame.height, oneLine.height + 20)
        XCTAssertEqual(field.frame.minX, oneLine.minX, accuracy: 1)
        XCTAssertEqual(field.frame.maxX, oneLine.maxX, accuracy: 1)

        app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "so Chef can plan the meals")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send"].exists)
    }

    @MainActor func testStopSitsInTheFieldWhenEmptyAndOnTheWorkingRowWhileTyping() {
        let app = launch("composer-running")
        let stops = app.buttons.matching(identifier: "Stop")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(stops.count, 2)

        _ = type("Use the staging context", in: app)
        XCTAssertTrue(app.buttons["Steer"].waitForExistence(timeout: 5))
        XCTAssertEqual(stops.count, 1)

        stops.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Stopped"].waitForExistence(timeout: 5))
        XCTAssertEqual(stops.count, 0)
        XCTAssertTrue(app.buttons["Send"].exists)
    }

    @MainActor func testTypingContinuesAtTheCaretWhenTheTurnFinishes() {
        let app = launch("composer-running", ["-finishTurnAfterDraft", "Use the staging context"])
        let field = type("Use the staging context", in: app)
        XCTAssertTrue(app.staticTexts["Deployed to staging."].waitForExistence(timeout: 10), "the turn finished")
        XCTAssertTrue(app.buttons["Send"].waitForExistence(timeout: 5), "the composer left the running state")
        field.typeText(" now")
        XCTAssertEqual(field.value as? String, "Use the staging context now")
    }
}
