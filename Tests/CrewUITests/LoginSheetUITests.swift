import XCTest

final class LoginSheetUITests: XCTestCase {
    @MainActor func testSavingClearsThePasswordWithoutFlaggingItAsMissing() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "edit-login", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        password.tap()
        password.typeText("correct horse")
        let save = app.buttons["Save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let cleared = NSPredicate(format: "isEnabled == false")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: save)], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["Enter the password."].exists)
    }
}
