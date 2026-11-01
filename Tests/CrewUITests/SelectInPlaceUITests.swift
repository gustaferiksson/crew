import UIKit
import XCTest

final class SelectInPlaceUITests: TranscriptUITestCase {
    private let summaryRequest = "Summarise everything we talked about in this chat so far as a numbered list, one or two sentences per item."

    @MainActor private func visible(_ predicate: NSPredicate, in app: XCUIApplication) -> XCUIElement? {
        app.staticTexts.matching(predicate).allElementsBoundByIndex.last { $0.isHittable }
    }

    @MainActor private func select(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        element.press(forDuration: 1)
        app.buttons["Select"].tap()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "no text view in the transcript after Select")
        XCTAssertFalse(app.navigationBars["Select Text"].exists, "Select opened a sheet")
        XCTAssertTrue(app.buttons["Attach"].exists, "the chat left the screen")
        shoot("selecting", in: app)
        return text
    }

    @MainActor private func copyFromTheEditMenu(in app: XCUIApplication) -> String? {
        let copy = app.menuItems["Copy"].exists ? app.menuItems["Copy"] : app.buttons["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "no edit menu over the selection")
        copy.tap()
        XCTAssertEqual(UIPasteboard.general.types, ["public.utf8-plain-text"], "copy wrote more than plain text")
        let field = app.textFields.firstMatch
        field.tap()
        field.tap()
        let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "no Paste in the composer")
        paste.tap()
        return field.value as? String
    }

    @MainActor func testSelectOnAReplySelectsItsRenderedTextInPlace() {
        let app = launch()
        assertRightAboveTheComposer(lastBlock, in: app, "opened")
        guard let reply = visible(lastBlock, in: app) else { return XCTFail("the last reply is not on screen") }
        let text = select(reply, in: app)
        let shown = text.value as? String ?? ""
        XCTAssertTrue(shown.contains("Dictionary(grouping:)"), shown)
        XCTAssertFalse(shown.contains("`"), "raw markdown in the selection: \(shown)")
        XCTAssertFalse(shown.contains("**"), "raw markdown in the selection: \(shown)")

        let copied = copyFromTheEditMenu(in: app) ?? ""
        XCTAssertTrue(copied.hasPrefix("1. Test purchase:"), copied)
        XCTAssertTrue(copied.contains("12. Swift date grouping: I provided a short function using Dictionary(grouping:)"), copied)
        XCTAssertFalse(copied.contains("`") || copied.contains("\t"), copied)

        XCTAssertFalse(app.textViews.firstMatch.exists, "focusing the composer left select mode on")
    }

    @MainActor func testSelectOnABubbleSelectsItsTextInPlace() {
        let app = launch()
        let request = NSPredicate(format: "label == %@", summaryRequest)
        for _ in 0..<8 where visible(request, in: app) == nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        guard let bubble = visible(request, in: app) else { return XCTFail("the summary request never came on screen") }
        let row = bubble.frame.midY
        let text = select(bubble, in: app)
        XCTAssertEqual(text.value as? String, summaryRequest)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 6, dy: row)).tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForNonExistence(timeout: 5), "a tap on the transcript left select mode on")
        XCTAssertTrue(bubble.exists)
    }
}
