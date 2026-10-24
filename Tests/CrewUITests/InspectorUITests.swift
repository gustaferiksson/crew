import XCTest

final class InspectorUITests: XCTestCase {
    @MainActor func testSegmentsSwitchTabsAndSwipeRemovesALoginOnlyAfterConfirming() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "inspector-passwords", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["Info"].tap()
        XCTAssertTrue(app.staticTexts["Last Active"].waitForExistence(timeout: 5))
        tabs.buttons["Passwords"].tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "github.com")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let log = app.descendants(matching: .any)["request-log"]
        row.swipeLeft()
        app.buttons["Remove"].tap()
        let confirm = app.buttons["Remove Login"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(log.value as? String, "none")
        confirm.tap()

        let removed = NSPredicate(format: "value == %@", "vault.remove vault_a1")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: removed, object: log)], timeout: 10), .completed)
    }
}
