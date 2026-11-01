import XCTest

private let title = "Brown sheepskin slippers"

final class PinnedCardUITests: XCTestCase {
    @MainActor func testTheNewestCardPinsAboveTheComposerOpensInASheetAndUnpinsOnlyFromTheX() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-a2ui-pinned", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let bar = app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", title, "Pinned card")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "pinned bar missing:\n\(app.debugDescription)")

        bar.tap()
        let sheet = app.navigationBars[title]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the card sheet should open")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(sheet.exists, "the card sheet should stay open")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "pinned-card-sheet"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let top = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "swiping down should close the sheet")
        XCTAssertTrue(bar.exists, "closing the sheet keeps the pin")

        app.buttons["Unpin"].firstMatch.tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "the X unpins")

        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(header.exists)
        header.press(forDuration: 1.2)
        let pin = app.buttons["Pin Card"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "the card's context menu should offer Pin Card")
        pin.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "Pin Card brings the bar back")
    }
}
