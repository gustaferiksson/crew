import XCTest

final class QuestionCardUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        return app
    }

    @MainActor private func choice(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    @MainActor private func question(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", text)).firstMatch
    }

    @MainActor func testStepsThroughThreeQuestionsAndSendsAllAnswers() {
        let app = launch("chat-questions")
        XCTAssertTrue(question("Where would you spend a free afternoon?", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Question 1 of 3. Where would you spend a free afternoon?"].exists)
        XCTAssertTrue(choice("By the lake", in: app).label.hasSuffix("Recommended"))
        XCTAssertFalse(app.buttons["Back"].exists)
        XCTAssertFalse(app.buttons["Next"].isEnabled)

        choice("In a bookshop", in: app).tap()
        XCTAssertTrue(question("Which snacks would you bring? Select as many as you like.", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Question 2 of 3"].exists)
        choice("Cinnamon buns", in: app).tap()
        choice("Fresh fruit", in: app).tap()
        choice("Crisps", in: app).tap()
        choice("Crisps", in: app).tap()
        XCTAssertTrue(choice("Cinnamon buns", in: app).isSelected)
        XCTAssertTrue(choice("Fresh fruit", in: app).isSelected)
        XCTAssertFalse(choice("Crisps", in: app).isSelected)
        XCTAssertTrue(app.staticTexts["Question 2 of 3"].exists)

        app.buttons["Back"].tap()
        XCTAssertTrue(question("Where would you spend a free afternoon?", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(choice("In a bookshop", in: app).isSelected)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Question 2 of 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(choice("Fresh fruit", in: app).isSelected)

        app.buttons["Next"].tap()
        XCTAssertTrue(question("What would you name a robot that waters your plants?", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Question 3 of 3"].exists)
        let send = app.buttons["Send"]
        XCTAssertFalse(send.isEnabled)
        let field = app.textFields["Your answer"].exists ? app.textFields["Your answer"] : app.textViews["Your answer"]
        field.tap()
        field.typeText("Sprout")
        XCTAssertTrue(send.isEnabled)
        send.tap()

        let log = app.descendants(matching: .any)["request-log"]
        let expected = #"clarify.respond {"q0":"In a bookshop","q1":"[\"Cinnamon buns\",\"Fresh fruit\"]","q2":"Sprout"}"#
        let sent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: log)
        XCTAssertEqual(XCTWaiter().wait(for: [sent], timeout: 10), .completed, String(describing: log.value))
    }

    @MainActor func testASingleQuestionHasNoPager() {
        let app = launch("chat-question")
        XCTAssertTrue(question("Which environment should I deploy to?", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Question 1 of 1"].exists)
        XCTAssertFalse(app.buttons["Back"].exists)
        XCTAssertFalse(app.buttons["Next"].exists)
        choice("Production", in: app).tap()
        XCTAssertTrue(choice("Production", in: app).isSelected)
        XCTAssertTrue(question("Which environment should I deploy to?", in: app).exists)
        app.buttons["Send"].tap()
        let log = app.descendants(matching: .any)["request-log"]
        let sent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", #"clarify.respond {"env":"Production"}"#), object: log)
        XCTAssertEqual(XCTWaiter().wait(for: [sent], timeout: 10), .completed, String(describing: log.value))
    }
}
