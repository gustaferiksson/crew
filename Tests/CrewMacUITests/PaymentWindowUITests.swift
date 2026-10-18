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
            let settled = NSPredicate(format: "frame.size.height < 480")
            XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: settled, object: window)], timeout: 10), .completed, "the window takes the short height")
            XCTAssertTrue(pay.isHittable)
            XCTAssertTrue(app.buttons["Deny payment"].isHittable)
            XCTAssertTrue(app.staticTexts["www.zalando.se"].isHittable)
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
