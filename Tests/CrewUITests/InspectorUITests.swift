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

    @MainActor func testTappingALoginAndTheShopButtonsOpenSheetsThatStayOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "inspector-passwords", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 10))

        let login = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "github.com")).firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        for (opener, title) in [(login, "Edit Login"), (app.buttons["Replace Card…"], "Replace Card"), (app.buttons["Add Shop…"], "Add Shop")] {
            for _ in 0..<8 where !(opener.exists && opener.isHittable) { app.swipeUp(velocity: .slow) }
            opener.tap()

            let sheet = app.navigationBars[title]
            XCTAssertTrue(sheet.waitForExistence(timeout: 5), title)
            let dismissed = NSPredicate(format: "exists == false")
            XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: sheet)], timeout: 3), .timedOut, title)
            sheet.buttons["Cancel"].tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), title)
        }
    }

    @MainActor func testAddConnectionSheetStaysOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "inspector-info", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let opener = app.buttons["Add Connection…"]
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 10))
        try app.auditHitRegionsAndClipping()
        for _ in 0..<10 where !(opener.exists && opener.isHittable) { app.swipeUp(velocity: .slow) }
        opener.tap()

        let sheet = app.navigationBars["Add Connection"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let dismissed = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: sheet)], timeout: 3), .timedOut)
    }

    @MainActor func testConnectionPageSheetStaysOpenAndListsTools() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "inspector-info", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let opener = app.buttons["Show Details"].firstMatch
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<10 where !(opener.exists && opener.isHittable) { app.swipeUp(velocity: .slow) }
        opener.tap()

        let sheet = app.navigationBars["DeepWiki"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let dismissed = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: sheet)], timeout: 3), .timedOut)
        XCTAssertTrue(app.staticTexts["ask_wiki_question"].exists)
        sheet.buttons["Done"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
    }
}
