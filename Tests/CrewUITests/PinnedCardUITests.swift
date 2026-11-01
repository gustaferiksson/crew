import XCTest

private let title = "Brown sheepskin slippers"

final class PinnedCardUITests: XCTestCase {
    @MainActor func testTheNewestCardPinsAboveTheComposerAndItsPreviewAndTheBarOpenOneSheet() {
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

        let preview = app.buttons.matching(NSPredicate(format: "label == %@ AND value != %@", title, "Pinned card")).firstMatch
        for _ in 0..<6 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.exists, "the transcript shows the card as a compact preview:\n\(app.debugDescription)")
        preview.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the preview opens the same card sheet")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(sheet.exists, "the card sheet opened from the transcript should stay open")
        app.buttons["Pin"].firstMatch.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "Pin in the sheet brings the bar back")
        XCTAssertTrue(sheet.exists, "pinning keeps the sheet open")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        app.buttons["Unpin"].firstMatch.tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
        preview.press(forDuration: 1.2)
        let pin = app.buttons["Pin Card"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "the preview's context menu should offer Pin Card")
        pin.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "Pin Card brings the bar back")
    }
}
