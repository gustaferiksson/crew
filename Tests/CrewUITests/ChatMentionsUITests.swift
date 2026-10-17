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
        XCTAssertFalse(app.buttons["Ada Lovelace, @ada"].exists)

        let bubble = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "to find flights for the Lofoten trip")).firstMatch
        XCTAssertTrue(bubble.exists)
        XCTAssertEqual(bubble.links.allElementsBoundByIndex.map(\.label), ["Scout", "Ada\u{00A0}Lovelace"])
        XCTAssertFalse(bubble.label.contains("@scout"))

        let message = app.staticTexts["Please find flights to Lofoten in March for two adults, flexible dates."]
        for _ in 0..<2 {
            bubble.links["Scout"].tap()

            XCTAssertTrue(message.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Found three options under 2 000 kr")).firstMatch.exists)
            XCTAssertTrue(bubble.exists)

            let header = message.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -80))
            header.press(forDuration: 0.1, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)))

            XCTAssertTrue(message.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars["Hermes"].waitForExistence(timeout: 5))
            XCTAssertEqual(composer.value as? String, "Loop in @ada and @sc")
        }
    }
}
