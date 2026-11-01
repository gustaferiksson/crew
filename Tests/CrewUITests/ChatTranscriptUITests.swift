import XCTest

final class ChatTranscriptUITests: TranscriptUITestCase {
    @MainActor func testALongChatOpensAtTheEndAndJumpToLatestBringsItBack() {
        let app = launch()
        assertRightAboveTheComposer(lastBlock, in: app, "opened")
        focusComposer(app)
        assertRightAboveTheComposer(lastBlock, in: app, "keyboard up")
        scrollUp(app)
        assertTheArrowHangsAboveTheComposer(in: app, "keyboard up")
        app.buttons["Jump to Latest"].tap()
        assertRightAboveTheComposer(lastBlock, in: app, "jumped")
        lowerKeyboard(app)
        assertRightAboveTheComposer(lastBlock, in: app, "keyboard down after the jump")
        scrollUp(app)
        assertTheArrowHangsAboveTheComposer(in: app, "keyboard down")
    }

    @MainActor func testAReplyArrivingWhileScrolledUpLeavesTheReaderAlone() {
        let app = launch()
        focusComposer(app)
        scrollUp(app)
        let reading = app.staticTexts.allElementsBoundByIndex.first { $0.frame.minY > 200 && $0.frame.maxY < 450 }
        let label = reading?.label ?? ""
        XCTAssertFalse(label.isEmpty)
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
        var readingTop = row.frame.minY
        for _ in 0..<10 {
            wait(0.5)
            if abs(row.frame.minY - readingTop) < 0.5 { break }
            readingTop = row.frame.minY
        }
        streamAReply(app)
        shoot("reply streamed while scrolled up", in: app)
        let moved = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.map { $0.frame.minY - readingTop }.min { abs($0) < abs($1) }
        XCTAssertEqual(moved ?? .infinity, 0, accuracy: 1, "the row being read moved")
        XCTAssertTrue(app.buttons["Jump to Latest"].exists)
        app.buttons["Jump to Latest"].tap()
        assertRightAboveTheComposer(streamedReply, in: app, "jumped to the reply from the Mac")
        scrollUp(app)

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
            _ = app.buttons["Jump to Latest"].waitForNonExistence(timeout: 1.5)
        }
        XCTAssertFalse(app.buttons["Jump to Latest"].exists, "never got back to the bottom by hand")
        streamAReply(app)
        assertRightAboveTheComposer(streamedReply, in: app, "reply after a manual return")
    }
}
