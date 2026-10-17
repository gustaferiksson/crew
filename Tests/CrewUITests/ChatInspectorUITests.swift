import XCTest

final class ChatInspectorUITests: XCTestCase {
    @MainActor func testComposerAndTranscriptReturnAfterTheInspectorWhileTyping() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "layout", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Half a thought")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }

        app.navigationBars.buttons["Ada Lovelace"].tap()
        XCTAssertTrue(app.staticTexts["Last Active"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let lastReply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The local build passes.")).firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isHittable)
        XCTAssertEqual(composer.value as? String, "Half a thought")
        XCTAssertTrue(lastReply.waitForExistence(timeout: 5))
        XCTAssertTrue(lastReply.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        print(app.debugDescription)
    }
}
