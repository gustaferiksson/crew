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
}
