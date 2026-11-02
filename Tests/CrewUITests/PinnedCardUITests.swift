import XCTest

private let title = "Brown sheepskin slippers"

final class PinnedCardUITests: XCTestCase {
    @MainActor func testTheNewestCardPinsAsAChipAboveTheComposerThatOpensTheSameSheetAsItsPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-a2ui-pinned", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let button = app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", title, "Pinned card")).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "the pinned card should be a chip:\n\(app.debugDescription)")
        XCTAssertFalse(app.navigationBars["Hermes"].buttons[title].exists, "the pin is no longer a navigation bar button")
        let attach = app.buttons["Attach"]
        XCTAssertTrue(button.frame.maxY <= attach.frame.minY && button.frame.maxY > attach.frame.minY - 40, "the chip sits just above the + button")
        XCTAssertEqual(button.frame.minX, attach.frame.minX, accuracy: 2, "the chip lines up with the + button")
        XCTAssertLessThan(button.frame.width, app.windows.firstMatch.frame.width * 0.8, "the chip hugs its content")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Unpin")).firstMatch.exists, "the chip has no X")

        button.tap()
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
        XCTAssertTrue(button.exists, "closing the sheet keeps the pin")

        button.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.buttons["Unpin"].tap()
        XCTAssertTrue(sheet.buttons["Pin"].waitForExistence(timeout: 5), "Unpin in the sheet keeps it open")
        XCTAssertTrue(button.waitForNonExistence(timeout: 5), "Unpin in the sheet removes the chip at once")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(button.waitForNonExistence(timeout: 5), "the chip goes once its card is unpinned")

        let preview = app.scrollViews.buttons[title].firstMatch
        XCTAssertTrue(preview.exists, "the transcript shows the card as a compact preview:\n\(app.debugDescription)")
        preview.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the preview opens the same card sheet")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(sheet.exists, "the card sheet opened from the transcript should stay open")
        sheet.buttons["Pin"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Pin in the sheet brings the chip back")
        XCTAssertTrue(sheet.exists, "pinning keeps the sheet open")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        button.press(forDuration: 1.2)
        let unpin = app.buttons["Unpin"].firstMatch
        XCTAssertTrue(unpin.waitForExistence(timeout: 5), "the chip's context menu offers Unpin")
        unpin.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 5), "Unpin from the chip's context menu removes it")

        preview.press(forDuration: 1.2)
        let pin = app.buttons["Pin Card"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "the preview's context menu should offer Pin Card")
        pin.tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Pin Card brings the chip back")

        button.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let other = app.buttons.matching(NSPredicate(format: "label == %@", "More slippers")).firstMatch
        other.tap()
        XCTAssertTrue(app.navigationBars["More slippers"].waitForExistence(timeout: 5), "tapping another preview under the medium sheet swaps to that card")
    }
}
