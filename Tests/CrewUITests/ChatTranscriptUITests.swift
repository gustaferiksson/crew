import XCTest

final class ChatTranscriptUITests: XCTestCase {
    private let history = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.long-replies.history.json").path
    private let lastBlock = NSPredicate(format: "label BEGINSWITH %@", "Swift date grouping:")
    private let streamedReply = NSPredicate(format: "label BEGINSWITH %@", "Line 1 of the reply from the Mac")

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "composer-line", "-server", "hermes.example.com", "-username", "gustaf", "-historyFile", history, "-historyCopies", "14", "-replyAfterDraft", "!"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func lowest(_ predicate: NSPredicate, in app: XCUIApplication) -> CGFloat? {
        app.staticTexts.matching(predicate).allElementsBoundByIndex.map(\.frame.maxY).max()
    }

    @MainActor private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: .now.addingTimeInterval(seconds))
    }

    @MainActor private func shoot(_ name: String, in app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor private func assertRightAboveTheComposer(_ predicate: NSPredicate, in app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
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

    @MainActor private func scrollUp(_ app: XCUIApplication) {
        for _ in 0..<3 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)), withVelocity: .fast, thenHoldForDuration: 0)
        }
        XCTAssertTrue(app.buttons["Jump to Latest"].waitForExistence(timeout: 5))
        wait(2)
    }

    @MainActor private func focusComposer(_ app: XCUIApplication) {
        app.textFields.firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor private func lowerKeyboard(_ app: XCUIApplication) {
        app.buttons["Hermes"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    @MainActor func testALongChatOpensAtTheEndAndJumpToLatestBringsItBack() {
        let app = launch()
        assertRightAboveTheComposer(lastBlock, in: app, "opened")
        focusComposer(app)
        assertRightAboveTheComposer(lastBlock, in: app, "keyboard up")
        for round in 1...3 {
            scrollUp(app)
            app.buttons["Jump to Latest"].tap()
            assertRightAboveTheComposer(lastBlock, in: app, "jump \(round)")
        }
        lowerKeyboard(app)
        assertRightAboveTheComposer(lastBlock, in: app, "keyboard down after the jumps")
    }

    @MainActor func testASendFromFarUpLandsRightAboveTheComposer() {
        let app = launch()
        focusComposer(app)
        scrollUp(app)
        app.buttons["Send"].tap()
        assertRightAboveTheComposer(NSPredicate(format: "label == %@", "On it."), in: app, "sent")
    }

    @MainActor func testAReplyArrivingWhileScrolledUpLeavesTheReaderAlone() {
        let app = launch()
        focusComposer(app)
        scrollUp(app)
        let reading = app.staticTexts.allElementsBoundByIndex.first { $0.frame.minY > 200 && $0.frame.maxY < 450 }
        XCTAssertNotNil(reading)
        let readingTop = reading?.frame.minY ?? 0
        app.textFields.firstMatch.typeText("!")
        wait(3.5)
        shoot("reply streamed while scrolled up", in: app)
        XCTAssertEqual(reading?.frame.minY ?? 0, readingTop, accuracy: 1, "the row being read moved")
        XCTAssertTrue(app.buttons["Jump to Latest"].exists)

        let headers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Worked for"))
        var header = headers.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < 450 }
        for _ in 0..<8 where header == nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0.3)
            wait(1)
            header = headers.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < 450 }
        }
        guard let header else { return XCTFail("no Worked for header on screen") }
        let headerTop = header.frame.minY
        header.tap()
        wait(1)
        shoot("work log expanded while scrolled up", in: app)
        XCTAssertEqual(header.frame.minY, headerTop, accuracy: 1, "the expanded header moved")
    }

    @MainActor func testAReplyArrivingAfterScrollingBackByHandStaysAboveTheComposer() {
        let app = launch()
        focusComposer(app)
        scrollUp(app)
        for _ in 0..<12 where app.buttons["Jump to Latest"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)), withVelocity: .fast, thenHoldForDuration: 0)
            wait(1.5)
        }
        XCTAssertFalse(app.buttons["Jump to Latest"].exists, "never got back to the bottom by hand")
        app.textFields.firstMatch.typeText("!")
        wait(3)
        assertRightAboveTheComposer(streamedReply, in: app, "reply after a manual return")
    }
}
