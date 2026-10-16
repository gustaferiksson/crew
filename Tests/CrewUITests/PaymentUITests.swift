import XCTest

final class PaymentUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        return app
    }

    @MainActor private func log(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["payment-log"].value as? String ?? ""
    }

    @MainActor private func waitForLog(_ expected: String, in app: XCUIApplication) -> Bool {
        let element = app.descendants(matching: .any)["payment-log"]
        let predicate = NSPredicate(format: "value == %@", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed
    }

    @MainActor func testCardShowsHostTotalAndClaim() {
        let app = launch("chat-payment")
        XCTAssertTrue(app.staticTexts["www.zalando.se"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["499 kr"].exists)
        XCTAssertTrue(app.staticTexts["Hermes states the amount and the shop. The card fills only on www.zalando.se."].exists)
        XCTAssertTrue(app.buttons["Hold to Pay"].exists)
        XCTAssertTrue(app.buttons["Deny payment"].exists)
    }

    @MainActor func testTapAsksForConfirmationAndCancelKeepsTheCard() {
        let app = launch("chat-payment")
        let pay = app.buttons["Hold to Pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 10))
        pay.tap()
        XCTAssertTrue(app.staticTexts["Pay 499 kr at www.zalando.se?"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(app.staticTexts["Pay 499 kr at www.zalando.se?"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(log(in: app), "none")
        XCTAssertTrue(pay.exists)
    }

    @MainActor func testTapThenPayApprovesOnce() {
        let app = launch("chat-payment")
        let pay = app.buttons["Hold to Pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 10))
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
        pay.press(forDuration: 1.2)
        XCTAssertFalse(app.staticTexts["Pay 499 kr at www.zalando.se?"].exists)
        XCTAssertTrue(waitForLog("approval.respond once", in: app))
        XCTAssertTrue(app.staticTexts["www.zalando.se"].waitForNonExistence(timeout: 5))
    }

    @MainActor func testShortPressSendsNothing() {
        let app = launch("chat-payment")
        let pay = app.buttons["Hold to Pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 10))
        pay.press(forDuration: 0.6)
        XCTAssertFalse(app.staticTexts["Pay 499 kr at www.zalando.se?"].waitForExistence(timeout: 1))
        XCTAssertEqual(log(in: app), "none")
        XCTAssertTrue(pay.exists)
    }

    @MainActor func testDenyAnswersAtOnce() {
        let app = launch("chat-payment")
        let deny = app.buttons["Deny payment"]
        XCTAssertTrue(deny.waitForExistence(timeout: 10))
        deny.tap()
        XCTAssertTrue(waitForLog("approval.respond deny", in: app))
        XCTAssertTrue(app.buttons["Hold to Pay"].waitForNonExistence(timeout: 5))
    }

    @MainActor func testUnverifiedCardOnlyDenies() {
        let app = launch("chat-payment-unverified")
        XCTAssertTrue(app.staticTexts["Crew can't verify this payment request."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Deny payment"].exists)
        XCTAssertFalse(app.buttons["Hold to Pay"].exists)
    }

    @MainActor func testEndedRequestNoticeDismisses() {
        let app = launch("chat-payment-notice")
        let ok = app.buttons["OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This payment request expired at")).firstMatch.exists)
        ok.tap()
        XCTAssertTrue(ok.waitForNonExistence(timeout: 5))
    }

    @MainActor func testOfferOpensAddShopFilledIn() {
        let app = launch("chat-payment-offer")
        let add = app.buttons["Add Shop…"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let field = app.textFields.matching(NSPredicate(format: "value == %@", "www.zalando.de")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["https://www.zalando.de"].exists)
    }
}
