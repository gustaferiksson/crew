import XCTest

final class LiveWorkLogUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        return app
    }

    @MainActor private func header(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        let headers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        return headers.element(boundBy: max(headers.count - 1, 0))
    }

    @MainActor private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    @MainActor func testARunningTurnWithNothingYetShowsOnlyTheHeader() {
        let app = launch("chat-waiting")
        XCTAssertTrue(header("Working for", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "How many files", in: app).exists)
    }

    @MainActor func testTheLiveLogStaysCollapsedAndTheHeaderHoldsItsPlaceWhenTheTurnEnds() {
        let app = launch("composer-running")
        let working = header("Working for", in: app)
        XCTAssertTrue(working.waitForExistence(timeout: 10))
        XCTAssertFalse(text(containing: "kubectl", in: app).exists)
        let prompt = text(containing: "Deploy it to staging", in: app)
        let liveHeader = working.frame
        let promptToHeader = liveHeader.minY - prompt.frame.minY

        app.buttons.matching(identifier: "Stop").firstMatch.tap()
        let stopped = app.staticTexts["Stopped"]
        XCTAssertTrue(stopped.waitForExistence(timeout: 5))
        let worked = header("Worked for", in: app)
        XCTAssertTrue(worked.exists)
        XCTAssertEqual(worked.frame.height, liveHeader.height, accuracy: 1)
        XCTAssertEqual(worked.frame.minY - prompt.frame.minY, promptToHeader, accuracy: 1)
        XCTAssertLessThan(stopped.frame.minY - worked.frame.maxY, 20)
    }

    @MainActor func testTappingTheLiveHeaderShowsTheLog() {
        let app = launch("composer-running")
        let working = header("Working for", in: app)
        XCTAssertTrue(working.waitForExistence(timeout: 10))
        XCTAssertFalse(text(containing: "kubectl", in: app).exists)

        working.tap()
        XCTAssertTrue(text(containing: "kubectl", in: app).waitForExistence(timeout: 5))
    }
}
