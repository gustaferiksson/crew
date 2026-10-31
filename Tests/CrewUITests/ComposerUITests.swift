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

    @MainActor func testSideMarginsAre28WithTheKeyboardHiddenAnd16WhileFocused() {
        let app = launch("composer-running")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let width = app.windows.firstMatch.frame.width
        let attach = app.buttons["Attach"]
        let stop = app.buttons.matching(identifier: "Stop").allElementsBoundByIndex.first { $0.frame.height == 32 }
        XCTAssertEqual(attach.frame.minX.rounded(), 28)
        XCTAssertEqual((width - (stop?.frame.maxX ?? 0) - 4).rounded(), 28)

        field.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
        let settled = NSPredicate { element, _ in (element as? XCUIElement)?.frame.minX.rounded() == 16 }
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: settled, object: attach)], timeout: 5)
        let focusedStop = app.buttons.matching(identifier: "Stop").allElementsBoundByIndex.first { $0.frame.height == 32 }
        XCTAssertEqual(attach.frame.minX.rounded(), 16)
        XCTAssertEqual((width - (focusedStop?.frame.maxX ?? 0) - 4).rounded(), 16)
    }
}
