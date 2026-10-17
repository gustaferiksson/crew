import XCTest

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
        XCTAssertTrue(openInSafari.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "in-app-browser"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Close"].tap()

        XCTAssertTrue(openInSafari.waitForNonExistence(timeout: 5))
        XCTAssertTrue(lastReply.isHittable)
        XCTAssertTrue(app.textFields.firstMatch.isHittable)
    }

    @MainActor func testLinkInAConversationSheetOpensSafariOverTheSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "sidebar-search", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let scoutHit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "in Ferries around Reine")).firstMatch
        XCTAssertTrue(scoutHit.waitForExistence(timeout: 10))
        scoutHit.tap()
        let sheet = app.navigationBars["Ferries around Reine"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        let link = app.links["PR #42"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let openInSafari = app.buttons["OpenInSafariButton"]
        XCTAssertTrue(openInSafari.waitForExistence(timeout: 10))
        app.buttons["Close"].tap()

        XCTAssertTrue(openInSafari.waitForNonExistence(timeout: 5))
        XCTAssertTrue(sheet.buttons["Done"].isHittable)

        sheet.buttons["Done"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Scout"].waitForExistence(timeout: 5))
    }
}
