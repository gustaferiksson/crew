import XCTest

private let title = "Brown sheepskin slippers"
private let item = "MJÙKA Idun · Brown"

final class CardExpandUITests: XCTestCase {
    @MainActor func testTheChevronExpandsTheCardInPlaceAndTheRowStillOpensTheSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-a2ui-pinned", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let preview = app.scrollViews.buttons[title].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 30), "the newest card's preview is missing:\n\(app.debugDescription)")
        let inline = app.scrollViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", item)).firstMatch
        XCTAssertFalse(inline.exists, "the card starts collapsed")

        let expand = app.scrollViews.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", "Expand", title)).firstMatch
        XCTAssertTrue(expand.exists, "the preview has a disclosure chevron:\n\(app.debugDescription)")
        expand.tap()
        XCTAssertTrue(inline.waitForExistence(timeout: 5), "the chevron shows the full card in the transcript")
        XCTAssertFalse(app.navigationBars[title].exists, "expanding opens no sheet")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "card-expanded"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        preview.tap()
        let sheet = app.navigationBars[title]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "tapping the row still opens the sheet")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(inline.exists, "the sheet leaves the inline card expanded")

        preview.press(forDuration: 1.2)
        let collapse = app.buttons["Collapse Card"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5), "the context menu offers Collapse Card")
        collapse.tap()
        XCTAssertTrue(inline.waitForNonExistence(timeout: 5), "Collapse Card folds the card back to its preview")
        XCTAssertTrue(preview.isHittable, "the transcript still shows the preview after collapsing")
    }
}
