import XCTest

// Safari's chrome lives in SafariViewService, which took over 5s to attach on a loaded CI runner.
private let safariAttachTimeout: TimeInterval = 30

final class InAppBrowserUITests: XCTestCase {
    @MainActor func testBotReplyLinkOpensSafariSheetOverTheChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "layout", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let lastReply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The local build passes.")).firstMatch
        XCTAssertTrue(lastReply.waitForExistence(timeout: 10))
        let link = app.links["PR #42"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()

        let openInSafari = app.buttons["OpenInSafariButton"]
        XCTAssertTrue(openInSafari.waitForExistence(timeout: safariAttachTimeout))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "in-app-browser"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Close"].tap()

        XCTAssertTrue(openInSafari.waitForNonExistence(timeout: 5))
        XCTAssertTrue(lastReply.isHittable)
        XCTAssertTrue(app.textFields.firstMatch.isHittable)
    }
}
