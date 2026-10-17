import XCTest

final class ChatKeyboardUITests: XCTestCase {
    @MainActor func testLastTurnStaysAboveTheComposerWhenTheKeyboardOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "layout", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let composer = app.textFields.firstMatch
        let lastReply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The local build passes.")).firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertTrue(lastReply.waitForExistence(timeout: 5))
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
        sleep(1)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(lastReply.isHittable)
        XCTAssertLessThanOrEqual(lastReply.frame.maxY, composer.frame.minY)
        XCTAssertGreaterThan(lastReply.frame.maxY, composer.frame.minY - 120)
        XCTAssertGreaterThanOrEqual(lastReply.frame.minY, app.navigationBars.firstMatch.frame.maxY)
    }
}
