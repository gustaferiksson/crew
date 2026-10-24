import XCTest

final class AccessibilityStateUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        return app
    }

    @MainActor func testWorkRowsReportTheirStateAndAnOpenThoughtSaysItsTextOnce() {
        let app = launch("chat-worklog")
        let openThoughts = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Thinking,"))
        XCTAssertTrue(openThoughts.firstMatch.waitForExistence(timeout: 10), "the open Thinking row is labelled just “Thinking” and its duration")
        XCTAssertEqual(openThoughts.firstMatch.value as? String, "Expanded")

        let closedThought = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Thinking The runner image")).firstMatch
        XCTAssertTrue(closedThought.exists, "a closed Thinking row keeps its preview")
        XCTAssertEqual(closedThought.value as? String, "Collapsed")
        closedThought.tap()
        XCTAssertEqual(openThoughts.count, 2)
    }

    @MainActor func testThePendingAttachmentRemoveButtonIsAFullTouchTarget() {
        let app = launch("chat-attachments")
        for name in ["Trailhead.png", "Lofoten itinerary.pdf"] {
            let remove = app.buttons["Remove \(name)"]
            XCTAssertTrue(remove.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(remove.frame.width, 44, name)
            XCTAssertGreaterThanOrEqual(remove.frame.height, 44, name)
        }
        let remove = app.buttons["Remove Trailhead.png"]
        let corner = CGVector(dx: remove.frame.maxX - 42, dy: remove.frame.minY + 42)
        app.coordinate(withNormalizedOffset: .zero).withOffset(corner).tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 3), "a tap 42 pt in from the glyph's corner removes the attachment")
    }
}
