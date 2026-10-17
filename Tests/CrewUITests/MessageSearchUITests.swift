import XCTest

final class MessageSearchUITests: XCTestCase {
    @MainActor func testTypingFindsMessagesAndAHitOpensTheChatAtIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "sidebar-search", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let hermesHit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Dry bag for the boat trip")).firstMatch
        XCTAssertTrue(hermesHit.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "in Ferries around Reine")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Messages"].exists)

        let field = app.searchFields.firstMatch
        field.tap()
        field.buttons.firstMatch.tap()
        field.typeText("picnic")

        let chefHit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "You: Pack something for a boat picnic")).firstMatch
        XCTAssertTrue(chefHit.waitForExistence(timeout: 5))
        XCTAssertFalse(hermesHit.exists)

        field.buttons.firstMatch.tap()
        field.typeText("zq")
        XCTAssertTrue(app.staticTexts["No Results for “zq”"].waitForExistence(timeout: 5))

        field.buttons.firstMatch.tap()
        field.typeText("boat")
        XCTAssertTrue(hermesHit.waitForExistence(timeout: 5))
        let match = app.staticTexts["Dry bag for the boat trip"]
        XCTAssertFalse(match.exists && match.isHittable)
        hermesHit.tap()

        XCTAssertTrue(app.navigationBars["Hermes"].waitForExistence(timeout: 5))
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        XCTAssertTrue(match.isHittable)
    }

    @MainActor func testAnOtherConversationHitOpensTheSheetOverTheBotsChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "sidebar-search", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let scoutHit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "in Ferries around Reine")).firstMatch
        XCTAssertTrue(scoutHit.waitForExistence(timeout: 10))
        scoutHit.tap()

        let sheet = app.navigationBars["Ferries around Reine"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.buttons["Done"].tap()

        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Scout"].waitForExistence(timeout: 5))
    }
}
