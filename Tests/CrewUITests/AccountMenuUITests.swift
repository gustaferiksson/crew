import XCTest

final class AccountMenuUITests: XCTestCase {
    @MainActor func testSetModelForAllBotsSitsAboveSignOut() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "sidebar", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let account = app.buttons["Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 30))
        account.tap()

        let setModel = app.buttons["Set Model for All Bots…"]
        let signOut = app.buttons["Sign Out"]
        XCTAssertTrue(setModel.waitForExistence(timeout: 10))
        XCTAssertTrue(signOut.exists)
        XCTAssertLessThan(setModel.frame.minY.rounded(), signOut.frame.minY.rounded())
    }
}
