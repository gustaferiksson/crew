import XCTest

final class DisclosureUITests: TranscriptUITestCase {
    @MainActor private func open(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        wait(1)
        return app
    }

    @MainActor private func tapTitle(_ header: XCUIElement) {
        header.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 44, dy: 0)).tap()
    }

    @MainActor private func assertRightAboveTheComposer(_ element: XCUIElement, in app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        wait(1)
        shoot(message, in: app)
        guard element.waitForExistence(timeout: 2) else { return XCTFail("\(message): not on screen", file: file, line: line) }
        let composerTop = app.buttons["Attach"].frame.minY
        let bottom = element.frame.maxY
        XCTAssertTrue(bottom <= composerTop && bottom > composerTop - 80, "\(message): ends at \(Int(bottom)), composer top \(Int(composerTop))", file: file, line: line)
        XCTAssertFalse(app.buttons["Jump to Latest"].exists, "\(message): Jump to Latest shows", file: file, line: line)
    }

    @MainActor func testOpeningTheLiveWorkLogAtTheEndShowsItAboveTheComposer() {
        let app = open("composer-running")
        focusComposer(app)
        tapTitle(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Working for")).firstMatch)
        assertRightAboveTheComposer(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ran kubectl")).firstMatch, in: app, "opened with the keyboard up")
        lowerKeyboard(app)
        let header = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Working for")).firstMatch
        tapTitle(header)
        assertRightAboveTheComposer(header, in: app, "closed")
        tapTitle(header)
        assertRightAboveTheComposer(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ran kubectl")).firstMatch, in: app, "opened again")
    }
}
