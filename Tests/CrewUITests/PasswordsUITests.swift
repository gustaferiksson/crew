import XCTest

final class PasswordsUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        return app
    }

    @MainActor private func log(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["request-log"].value as? String ?? ""
    }

    @MainActor private func waitForLog(_ expected: String, in app: XCUIApplication) -> Bool {
        let element = app.descendants(matching: .any)["request-log"]
        let predicate = NSPredicate(format: "value == %@", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    @MainActor func testAddLoginValidatesAndSendsOneRequestWithoutThePassword() {
        let app = launch("inspector-passwords")
        let add = app.buttons["Add Login…"]
        XCTAssertTrue(app.staticTexts["github.com"].waitForExistence(timeout: 10))
        reveal(add, in: app)
        add.tap()

        let website = app.textFields["Website"]
        XCTAssertTrue(website.waitForExistence(timeout: 5))
        website.tap()
        website.typeText("not a site")
        app.textFields["Username or Email"].tap()
        XCTAssertTrue(app.staticTexts["Enter the site's address, such as www.example.com."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add"].isEnabled)

        website.tap()
        website.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "https://www.notion.so/login\n")
        app.typeText("ada@example.com\n")
        app.typeText("correct horse battery")
        XCTAssertTrue(app.buttons["Add"].isEnabled)
        app.buttons["Add"].tap()

        XCTAssertTrue(waitForLog("vault.add www.notion.so ada@example.com", in: app))
        XCTAssertFalse(log(in: app).contains("horse"))
        XCTAssertTrue(website.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    @MainActor func testRemoveAsksFirst() {
        let app = launch("inspector-passwords")
        let row = app.staticTexts["github.com"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        reveal(row, in: app)
        row.press(forDuration: 1.2)
        let remove = app.buttons["Remove Login…"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertEqual(log(in: app), "none")
        let confirm = app.buttons["Remove Login"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(waitForLog("vault.remove vault_a1", in: app))
    }

    @MainActor func testOneTimeCodeLoginsCannotBeEdited() {
        let app = launch("inspector-passwords")
        let row = app.staticTexts["accounts.google.com"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        reveal(row, in: app)
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Remove Login…"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit Login…"].exists)
    }

    @MainActor func testConnectOnePasswordSendsTheTokenOnce() {
        let app = launch("inspector-passwords-empty")
        let connect = app.buttons["Connect…"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        reveal(connect, in: app)
        connect.tap()
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Connect"].isEnabled)
        field.tap()
        field.typeText("ops_eyJzaWduSW5BZGRyZXNzIjoibXkuMXBhc3N3b3JkLmNvbSJ9")
        app.buttons["Connect"].tap()
        XCTAssertTrue(waitForLog("env.put OP_SERVICE_ACCOUNT_TOKEN", in: app))
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Disconnect…"].waitForExistence(timeout: 5))
    }
}
