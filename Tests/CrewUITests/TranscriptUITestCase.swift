import XCTest

class TranscriptUITestCase: XCTestCase {
    let history = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.long-replies.history.json").path
    let lastBlock = NSPredicate(format: "label BEGINSWITH %@", "Swift date grouping:")
    let streamedReply = NSPredicate(format: "label BEGINSWITH %@", "Line 1 of the reply from the Mac")

    @MainActor func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "composer-line", "-server", "hermes.example.com", "-username", "gustaf", "-historyFile", history, "-historyCopies", "14", "-replyAfterDraft", "!"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor func lowest(_ predicate: NSPredicate, in app: XCUIApplication) -> CGFloat? {
        app.staticTexts.matching(predicate).allElementsBoundByIndex.map(\.frame.maxY).max()
    }

    @MainActor func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: .now.addingTimeInterval(seconds))
    }

    @MainActor func streamAReply(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.textFields.firstMatch.typeText("!")
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "idle"), object: app.descendants(matching: .any)["stream-state"])
        XCTAssertEqual(XCTWaiter().wait(for: [idle], timeout: 10), .completed, "the reply never finished streaming", file: file, line: line)
    }

    @MainActor func shoot(_ name: String, in app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func assertRightAboveTheComposer(_ predicate: NSPredicate, in app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date.now.addingTimeInterval(5)
        var composerTop = app.buttons["Attach"].frame.minY
        var bottom = lowest(predicate, in: app)
        while Date.now < deadline, !(bottom.map { $0 <= composerTop && $0 > composerTop - 80 } ?? false) || app.buttons["Jump to Latest"].exists {
            wait(0.25)
            composerTop = app.buttons["Attach"].frame.minY
            bottom = lowest(predicate, in: app)
        }
        shoot(message, in: app)
        XCTAssertTrue(bottom.map { $0 <= composerTop && $0 > composerTop - 80 } ?? false, "\(message): \(bottom.map { "ends at \(Int($0))" } ?? "not on screen"), composer top \(Int(composerTop))", file: file, line: line)
        XCTAssertFalse(app.buttons["Jump to Latest"].exists, "\(message): Jump to Latest still shows", file: file, line: line)
    }

    @MainActor func assertTheArrowHangsAboveTheComposer(in app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let gap = app.buttons["Attach"].frame.minY - app.buttons["Jump to Latest"].frame.maxY
        XCTAssertEqual(gap, 12, accuracy: 2, "\(message): the arrow hangs \(Int(gap)) pt above the composer", file: file, line: line)
    }

    @MainActor func scrollUp(_ app: XCUIApplication) {
        for _ in 0..<8 where lowest(lastBlock, in: app) != nil || lowest(streamedReply, in: app) != nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)), withVelocity: .fast, thenHoldForDuration: 0)
        }
        XCTAssertTrue(app.buttons["Jump to Latest"].waitForExistence(timeout: 5))
        wait(1)
    }

    @MainActor func focusComposer(_ app: XCUIApplication) {
        app.textFields.firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func lowerKeyboard(_ app: XCUIApplication) {
        app.buttons["Hermes"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
}
