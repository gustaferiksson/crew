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
            let host = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "zalando", "zalando")).firstMatch
            XCTAssertTrue(host.exists && host.isHittable, app.debugDescription)
            XCTAssertTrue(app.staticTexts["499 kr"].isHittable)
            XCTAssertTrue(app.staticTexts["Hermes wants to pay"].isHittable)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tree-\(appearance.lowercased())"
            tree.lifetime = .keepAlways
            add(tree)
            let shot = XCTAttachment(screenshot: window.screenshot())
            shot.name = "payment-short-window-\(appearance.lowercased())"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
