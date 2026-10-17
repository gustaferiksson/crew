import XCTest

final class WaitingDotsUITests: XCTestCase {
    @MainActor func testARunningTurnWithNothingYetShowsTheDotsUntilItEnds() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-waiting", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let dots = app.otherElements["Thinking"]
        XCTAssertTrue(dots.waitForExistence(timeout: 10))

        app.buttons.matching(identifier: "Stop").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Stopped"].waitForExistence(timeout: 5))
        XCTAssertFalse(dots.exists)
    }
}
