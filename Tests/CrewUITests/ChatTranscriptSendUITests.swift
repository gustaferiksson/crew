import XCTest

final class ChatTranscriptSendUITests: TranscriptUITestCase {
    @MainActor func testASendFromFarUpLandsRightAboveTheComposer() {
        let app = launch()
        focusComposer(app)
        scrollUp(app)
        app.buttons["Send"].tap()
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("A send from far up can still leave the transcript blank on iOS 27, LazyVStack estimates (#162)", options: options) {
            assertRightAboveTheComposer(NSPredicate(format: "label == %@", "On it."), in: app, "sent")
        }
    }

    @MainActor func testSendingAtTheEndWithTheKeyboardUpKeepsTheTurnAboveTheComposer() {
        let app = launch()
        focusComposer(app)
        assertRightAboveTheComposer(lastBlock, in: app, "keyboard up")
        app.buttons["Send"].tap()
        assertRightAboveTheComposer(NSPredicate(format: "label == %@", "On it."), in: app, "first send")
        app.textFields.firstMatch.typeText("Next one")
        app.buttons["Send"].tap()
        assertRightAboveTheComposer(NSPredicate(format: "label == %@", "On it."), in: app, "second send")
    }

    @MainActor func testAReplyAfterExpandingJumpingAndABouncedReturnStaysAboveTheComposer() {
        let app = launch()
        focusComposer(app)
        scrollUp(app)
        streamAReply(app)
        app.buttons["Jump to Latest"].tap()
        assertRightAboveTheComposer(streamedReply, in: app, "jumped to the reply")
        scrollUp(app)
        let headers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Worked for"))
        var header = headers.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < 450 }
        for _ in 0..<8 where header == nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0.3)
            wait(1)
            header = headers.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < 450 }
        }
        guard let header else { return XCTFail("no Worked for header on screen") }
        header.tap()
        wait(1)
        app.buttons["Jump to Latest"].tap()
        assertRightAboveTheComposer(streamedReply, in: app, "jumped after expanding")
        scrollUp(app)
        for _ in 0..<12 where app.buttons["Jump to Latest"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)), withVelocity: .fast, thenHoldForDuration: 0)
            _ = app.buttons["Jump to Latest"].waitForNonExistence(timeout: 1.5)
        }
        XCTAssertFalse(app.buttons["Jump to Latest"].exists, "never got back to the bottom by hand")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.33)), withVelocity: .slow, thenHoldForDuration: 0)
        wait(1.5)
        streamAReply(app)
        assertRightAboveTheComposer(streamedReply, in: app, "reply after a bounced return")
    }

    @MainActor func testACardInTheBarKeepsTheLatestReplyAboveIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-question", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        let card = app.staticTexts["Hermes has a question"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let working = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Working for")).firstMatch
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline, !(working.exists && working.frame.maxY <= card.frame.minY && !app.buttons["Jump to Latest"].exists) {
            wait(0.25)
        }
        shoot("question card", in: app)
        XCTAssertTrue(working.exists && working.frame.maxY <= card.frame.minY, "the running turn sits under the card")
        XCTAssertFalse(app.buttons["Jump to Latest"].exists)
    }
}
