import XCTest

final class ChatMentionsUITests: XCTestCase {
    @MainActor func testTappingAMentionTagKeepsTheChatOnScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-mentions", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "Loop in @ada and @sc")
        XCTAssertTrue(app.buttons["Scout, @scout"].exists)
        XCTAssertFalse(app.buttons["Ada, @ada"].exists)

        let bubble = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Can you ask @scout")).firstMatch
        let tag = bubble.links["crew-bot:scout"]
        XCTAssertTrue(bubble.exists)
        XCTAssertEqual(tag.label, "@scout")
        XCTAssertFalse(bubble.links["crew-bot:default"].exists)

        tag.tap()

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.navigationBars["Hermes"].exists)
        XCTAssertTrue(bubble.exists)
        XCTAssertTrue(composer.exists)
    }
}
