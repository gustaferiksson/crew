import XCTest

final class PaymentWindowUITests: XCTestCase {
    @MainActor func testShortWindowKeepsHostTotalAndHoldToPay() {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-snapshot", "chat-payment", "-snapshotHeight", "360", "-uiTest", "YES", "-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", appearance, "-server", "hermes.example.com", "-username", "gustaf"]
            app.launch()
            let pay = app.buttons["Hold to Pay"]
            XCTAssertTrue(pay.waitForExistence(timeout: 20))
            let window = app.windows.firstMatch
            XCTAssertLessThan(window.frame.height, 480, "the window takes the short height")
            let composer = window.textFields.firstMatch.exists ? window.textFields.firstMatch : window.textViews.firstMatch
            let host = app.staticTexts.matching(NSPredicate(format: "value == %@", "Pay, www.zalando.se")).firstMatch
            for element in [app.staticTexts["Hermes wants to pay"], host, app.staticTexts["499 kr"], app.buttons["Deny payment"], pay] {
                XCTAssertTrue(element.isHittable, element.description)
                XCTAssertGreaterThanOrEqual(element.frame.minY, window.frame.minY, element.description)
                XCTAssertLessThanOrEqual(element.frame.maxY, composer.frame.minY, element.description)
            }
            let shot = XCTAttachment(screenshot: window.screenshot())
            shot.name = "payment-short-window-\(appearance.lowercased())"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
