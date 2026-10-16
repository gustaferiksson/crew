import XCTest

final class ChatMentionsUITests: XCTestCase {
    @MainActor func testTappingAMentionTagPeeksWithoutLeavingTheChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-mentions", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "Loop in @ada and @sc")
        XCTAssertTrue(app.buttons["Scout, @scout"].exists)
        XCTAssertFalse(app.buttons["Ada, @ada"].exists)

        let bubble = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "to find flights for the Lofoten trip")).firstMatch
        let tag = bubble.links.matching(NSPredicate(format: "label == %@", "@scout")).firstMatch
        XCTAssertTrue(bubble.exists)
        XCTAssertTrue(tag.exists)
        XCTAssertEqual(bubble.links.count, 2)

        tag.tap()

        let message = app.staticTexts["Please find flights to Lofoten in March for two adults, flexible dates."]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Found three options under 2 000 kr")).firstMatch.exists)
        XCTAssertTrue(app.navigationBars["Hermes"].exists)
        XCTAssertTrue(bubble.exists)

        message.swipeDown(velocity: .fast)

        XCTAssertTrue(message.waitForNonExistence(timeout: 5))
        XCTAssertTrue(composer.exists)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
