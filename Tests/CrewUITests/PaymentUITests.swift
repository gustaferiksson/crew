import XCTest

final class PaymentUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"] + arguments
        app.launch()
        return app
    }

    @MainActor private func log(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["request-log"].value as? String ?? ""
    }

    @MainActor private func waitForLog(_ expected: String, in app: XCUIApplication) -> Bool {
        let element = app.descendants(matching: .any)["request-log"]
        let predicate = NSPredicate(format: "value == %@", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }

    @MainActor func testCardShowsTheClaimAndOnlyAConfirmedTapPays() {
        let app = launch("chat-payment")
        let pay = app.buttons["Hold to Pay"]
        let dialog = app.staticTexts["Pay 499 kr at www.zalando.se?"]
        XCTAssertTrue(app.staticTexts["www.zalando.se"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["499 kr"].exists)
        XCTAssertTrue(app.staticTexts["Hermes states the amount and the shop. The card fills only on www.zalando.se."].exists)
        XCTAssertTrue(pay.exists)
        XCTAssertTrue(app.buttons["Deny payment"].exists)

        pay.press(forDuration: 0.6)
        XCTAssertFalse(dialog.waitForExistence(timeout: 1))
        XCTAssertEqual(log(in: app), "none")
        XCTAssertTrue(pay.exists)

        pay.tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 5))
        XCTAssertEqual(log(in: app), "none")
        XCTAssertTrue(pay.exists)

        pay.tap()
        let confirm = app.buttons["Pay"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(waitForLog("approval.respond once", in: app))
    }

    @MainActor func testHoldingApprovesWithoutADialog() {
        let app = launch("chat-payment")
        let pay = app.buttons["Hold to Pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 10))
        pay.press(forDuration: 2)
        XCTAssertFalse(app.staticTexts["Pay 499 kr at www.zalando.se?"].exists)
        XCTAssertTrue(waitForLog("approval.respond once", in: app))
        XCTAssertTrue(app.staticTexts["www.zalando.se"].waitForNonExistence(timeout: 15))
    }

    @MainActor private func assertHostTotalAndHoldVisible(in app: XCUIApplication, host: String = "www.zalando.se") {
        let pay = app.buttons["Hold to Pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = app.textFields.firstMatch.frame.minY
        for element in [app.staticTexts["Hermes wants to pay"], app.staticTexts[host], app.staticTexts["499 kr"], app.buttons["Deny payment"], pay] {
            XCTAssertTrue(element.isHittable, element.description)
            XCTAssertGreaterThanOrEqual(element.frame.minY, top, element.description)
            XCTAssertLessThanOrEqual(element.frame.maxY, bottom, element.description)
        }
        XCTAssertFalse(app.buttons["Pay…"].exists)
    }
}
