import XCTest

final class ChatSendScrollUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf", "-earlierTurns", "24"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func type(_ text: String, in app: XCUIApplication) {
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText(text)
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
    }

    @MainActor private func assertAboveComposer(_ texts: [String], in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let elements = texts.map { app.staticTexts.matching(NSPredicate(format: "label == %@", $0)).firstMatch }
        elements.forEach { XCTAssertTrue($0.waitForExistence(timeout: 5), file: file, line: line) }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .deleteOnSuccess
        add(shot)
        let composerTop = app.buttons["Attach"].frame.minY
        for element in elements {
            XCTAssertLessThanOrEqual(element.frame.maxY, composerTop, "\(element.label) ends under the composer", file: file, line: line)
            XCTAssertGreaterThanOrEqual(element.frame.minY, app.navigationBars.firstMatch.frame.maxY, "\(element.label) starts under the header", file: file, line: line)
        }
        XCTAssertGreaterThan(elements.last?.frame.maxY ?? 0, composerTop - 120, "the transcript is not pinned to the bottom", file: file, line: line)
    }

    @MainActor func testEverySendSitsRightAboveTheComposer() {
        let app = launch("composer-line")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 5))
        assertAboveComposer(["Sounds good, book the 07:10", "On it."], in: app)

        let multiLine = "Book the 07:10 and put the confirmation in the trip notes so Chef can plan the meals around the flight"
        type(multiLine, in: app)
        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 5))
        assertAboveComposer([multiLine], in: app)

        type("Short", in: app)
        app.buttons["Send"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 5))
        assertAboveComposer(["Short"], in: app)
    }

    @MainActor func testEverySendAfterTouchingTheTranscriptSitsRightAboveTheComposer() {
        let app = launch("composer-line")
        app.textFields.firstMatch.tap()
        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 5))
        assertAboveComposer(["Sounds good, book the 07:10"], in: app)
        for index in 1...2 {
            let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: CGFloat(index * 2))), withVelocity: 40, thenHoldForDuration: 0.3)
            type("Nudged \(index)", in: app)
            app.buttons["Send"].tap()
            XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 5))
            assertAboveComposer(["Nudged \(index)"], in: app)
        }
    }

    @MainActor func testASendWhileScrolledUpJumpsToTheBottom() {
        let app = launch("composer-line")
        let reply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The local build passes.")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.swipeDown()
        XCTAssertTrue(app.buttons["Jump to Latest"].waitForExistence(timeout: 5))
        app.textFields.firstMatch.tap()
        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 5))
        assertAboveComposer(["Sounds good, book the 07:10", "On it."], in: app)
        XCTAssertFalse(app.buttons["Jump to Latest"].exists)
    }

    @MainActor func testASteerWaitsThenSplitsTheRunRightAboveTheComposer() {
        let app = launch("composer-running")
        let text = "Use the staging context, not prod, and keep the old pods until the health checks pass"
        type(text, in: app)
        let start = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The local build passes.")).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 4)), withVelocity: 40, thenHoldForDuration: 0.3)
        app.textFields.firstMatch.tap()
        app.buttons["Steer"].tap()
        XCTAssertTrue(app.staticTexts["Waiting"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[text].exists)
        XCTAssertTrue(app.staticTexts["Waiting"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Worked for")).firstMatch.exists)
        assertAboveComposer([text, "Good call, switching to the staging context."], in: app)
    }

    @MainActor func testAQueuedMessageWaitsThenBecomesTheNextTurnRightAboveTheComposer() {
        let app = launch("composer-running")
        let text = "Then post the rollout in #deploys"
        type(text, in: app)
        let start = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The local build passes.")).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 4)), withVelocity: 40, thenHoldForDuration: 0.3)
        app.textFields.firstMatch.tap()
        app.buttons["Steer"].press(forDuration: 1)
        app.buttons["Queue"].tap()
        XCTAssertTrue(app.staticTexts["Queued"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Waiting"].exists)
        XCTAssertTrue(app.staticTexts[text].exists)
        XCTAssertTrue(app.staticTexts["Queued"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Applied to staging."].exists)
        assertAboveComposer([text], in: app)
    }
}
