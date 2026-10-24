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

    @MainActor private func eventually(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            if Date.now > deadline { return false }
            wait(0.25)
        }
        return true
    }

    @MainActor private func shoot(_ name: String, in app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor private func assertRightAboveTheComposer(_ predicate: NSPredicate, in app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let landed = eventually {
            let composerTop = app.buttons["Attach"].frame.minY
            return lowest(predicate, in: app).map { $0 <= composerTop && $0 > composerTop - 80 } == true && !app.buttons["Jump to Latest"].exists
        }
        shoot(message, in: app)
        let composerTop = app.buttons["Attach"].frame.minY
        XCTAssertTrue(landed, "\(message): \(lowest(predicate, in: app).map { "ends at \(Int($0))" } ?? "not on screen"), composer top \(Int(composerTop)), arrow \(app.buttons["Jump to Latest"].exists)", file: file, line: line)
    }

    @MainActor private func scrollUp(_ app: XCUIApplication) {
        for _ in 0..<8 where lowest(lastBlock, in: app) != nil || lowest(streamedReply, in: app) != nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)), withVelocity: .fast, thenHoldForDuration: 0)
            wait(0.5)
        }
        XCTAssertTrue(app.buttons["Jump to Latest"].waitForExistence(timeout: 5))
        wait(1)
    }

    @MainActor func testALongChatOpensAtTheEndJumpsBackAndSendsFromFarUp() {
        let app = launch()
        assertRightAboveTheComposer(lastBlock, in: app, "opened")
        app.textFields.firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        assertRightAboveTheComposer(lastBlock, in: app, "keyboard up")
        scrollUp(app)
        app.buttons["Jump to Latest"].tap()
        assertRightAboveTheComposer(lastBlock, in: app, "jumped with the keyboard up")
        scrollUp(app)
        app.buttons["Send"].tap()
        assertRightAboveTheComposer(NSPredicate(format: "label == %@", "On it."), in: app, "sent from far up")
        app.buttons["Hermes"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        assertRightAboveTheComposer(NSPredicate(format: "label == %@", "On it."), in: app, "keyboard down")
    }

    @MainActor func testRepliesFromAnotherClientLeaveTheReaderAloneAndFollowTheEnd() {
        let app = launch()
        let field = app.textFields.firstMatch
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        scrollUp(app)
        let label = app.staticTexts.allElementsBoundByIndex.first { $0.frame.minY > 200 && $0.frame.maxY < 450 }?.label ?? ""
        XCTAssertFalse(label.isEmpty)
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
        var readingTop = row.frame.minY
        for _ in 0..<10 {
            wait(0.5)
            if abs(row.frame.minY - readingTop) < 0.5 { break }
            readingTop = row.frame.minY
        }
        field.typeText("!")
        wait(3)
        shoot("reply streamed while scrolled up", in: app)
        let moved = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.map { $0.frame.minY - readingTop }.min { abs($0) < abs($1) }
        XCTAssertEqual(moved ?? .infinity, 0, accuracy: 1, "the row being read moved")
        XCTAssertTrue(app.buttons["Jump to Latest"].exists)

        let headers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Worked for"))
        var header = headers.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < 450 }
        for _ in 0..<16 where header == nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0.3)
            wait(1)
            header = headers.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < 450 }
        }
        guard let header else { return XCTFail("no Worked for header on screen") }
        let headerTop = header.frame.minY
        header.tap()
        wait(1)
        XCTAssertEqual(header.frame.minY, headerTop, accuracy: 1, "the expanded header moved")

        app.buttons["Jump to Latest"].tap()
        assertRightAboveTheComposer(streamedReply, in: app, "jumped to the reply from the Mac")
        scrollUp(app)
        for _ in 0..<12 where app.buttons["Jump to Latest"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)), withVelocity: .fast, thenHoldForDuration: 0)
            wait(1.5)
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)), withVelocity: .slow, thenHoldForDuration: 0.5)
        wait(1)
        XCTAssertFalse(app.buttons["Jump to Latest"].exists, "never got back to the bottom by hand")
        field.typeText("!")
        wait(3)
        assertRightAboveTheComposer(streamedReply, in: app, "reply after a manual return")
    }

    @MainActor func testACardInTheBarKeepsTheLatestReplyAboveIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-question", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        let card = app.staticTexts["Hermes has a question"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let working = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Working for")).firstMatch
        let settled = eventually { working.exists && working.frame.maxY <= card.frame.minY && !app.buttons["Jump to Latest"].exists }
        shoot("question card", in: app)
        XCTAssertTrue(settled, "the running turn sits under the card or Jump to Latest shows")
    }
}
