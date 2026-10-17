import XCTest

final class PaymentUITests: XCTestCase {
    @MainActor private func launch(_ snapshot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", snapshot, "-server", "hermes.example.com", "-username", "gustaf"]
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

    @MainActor func testAddCardValidatesSendsOnceAndForgetsTheFields() {
        let app = launch("inspector-shops-no-card")
        let addCard = app.buttons["Add Card…"]
        let number = app.textFields["Card Number"]
        let expiry = app.textFields["Expiry"]
        let code = app.secureTextFields["Security Code"]
        let add = app.buttons["Add"]
        XCTAssertTrue(addCard.waitForExistence(timeout: 10))
        addCard.tap()
        XCTAssertTrue(number.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)

        number.tap()
        "4242424242424241".forEach { number.typeText(String($0)) }
        expiry.tap()
        XCTAssertTrue(app.staticTexts["Check the card number."].waitForExistence(timeout: 5))
        "0825".forEach { expiry.typeText(String($0)) }
        XCTAssertEqual(expiry.value as? String, "08/25")
        code.tap()
        XCTAssertTrue(app.staticTexts["This card has expired."].waitForExistence(timeout: 5))
        code.typeText("123")
        XCTAssertFalse(add.isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(number.waitForNonExistence(timeout: 5))
        XCTAssertEqual(log(in: app), "none")

        addCard.tap()
        XCTAssertTrue(number.waitForExistence(timeout: 5))
        XCTAssertNotEqual(number.value as? String, "4242 4242 4242 4241")
        XCTAssertFalse(app.staticTexts["Check the card number."].exists)
        number.tap()
        "4242424242424242".forEach { number.typeText(String($0)) }
        XCTAssertEqual(number.value as? String, "4242 4242 4242 4242")
        let expiryFocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: expiry)
        XCTAssertEqual(XCTWaiter().wait(for: [expiryFocused], timeout: 5), .completed)
        "1230".forEach { expiry.typeText(String($0)) }
        XCTAssertEqual(expiry.value as? String, "12/30")
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: code)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed)
        code.typeText("123")
        XCTAssertFalse(app.staticTexts["Check the card number."].exists)
        XCTAssertFalse(app.staticTexts["This card has expired."].exists)
        XCTAssertTrue(add.isEnabled)
        add.tap()

        XCTAssertTrue(waitForLog("card Shopping card 12/2030", in: app))
        XCTAssertTrue(number.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Shopping card", "•••• 4242")).firstMatch.waitForExistence(timeout: 5))

        app.buttons["Replace Card…"].tap()
        XCTAssertTrue(number.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Replace Card"].exists)
        XCTAssertNotEqual(number.value as? String, "4242 4242 4242 4242")
        XCTAssertNotEqual(expiry.value as? String, "12/30")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(number.waitForNonExistence(timeout: 5))
        XCTAssertEqual(log(in: app), "card Shopping card 12/2030")
    }
}
