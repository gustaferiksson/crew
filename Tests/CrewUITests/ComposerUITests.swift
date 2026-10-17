import XCTest

final class ComposerUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"]
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

    @MainActor func testAQueuedMessageWaitsThenBecomesTheNextTurn() {
        let app = launch("composer-running")
        _ = type("Then post the rollout in #deploys", in: app)
        app.buttons["Steer"].press(forDuration: 1)
        app.buttons["Queue"].tap()

        let bubble = app.staticTexts["Then post the rollout in #deploys"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Queued"].exists)
        XCTAssertFalse(app.staticTexts["Waiting"].exists)
        XCTAssertTrue(app.staticTexts["Queued"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(bubble.exists)
        XCTAssertTrue(app.staticTexts["Applied to staging."].exists)
    }

    @MainActor func testASteerWaitsThenSplitsTheRunWithItsAnswer() {
        let app = launch("composer-running")
        _ = type("Use the staging context, not prod", in: app)
        app.buttons["Steer"].tap()

        XCTAssertTrue(app.staticTexts["Use the staging context, not prod"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Waiting"].exists)
        XCTAssertTrue(app.staticTexts["Waiting"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Good call, switching to the staging context."].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Worked for")).firstMatch.exists)
    }
}
