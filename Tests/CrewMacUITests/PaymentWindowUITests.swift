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
            XCTAssertTrue(pay.isHittable)
            XCTAssertTrue(app.buttons["Deny payment"].isHittable)
            let host = NSPredicate(format: "label CONTAINS %@ AND NOT (label BEGINSWITH %@)", "www.zalando.se", "Payment request")
            XCTAssertTrue(app.staticTexts.matching(host).firstMatch.isHittable)
            XCTAssertTrue(app.staticTexts["499 kr"].isHittable)
            XCTAssertTrue(app.staticTexts["Hermes wants to pay"].isHittable)
            let shot = XCTAttachment(screenshot: window.screenshot())
            shot.name = "payment-short-window-\(appearance.lowercased())"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
