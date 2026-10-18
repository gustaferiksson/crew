import XCTest

final class NotificationTapUITests: XCTestCase {
    @MainActor private func launch(notifyAfter seconds: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "sidebar", "-server", "hermes.example.com", "-username", "gustaf", "-uiTest", "YES", "-notifyProfile", "ada", "-notifyAfter", "\(seconds)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Ada Lovelace"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func tapInNotificationCenter(after seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.005)).press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        let notification = springboard.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Done with the migration dry run.")).matching(identifier: "ShortLook.Platter.Content.Seamless").firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        notification.tap()
    }

    @MainActor private func assertChatOpens(in app: XCUIApplication) {
        XCTAssertEqual(app.wait(for: .runningForeground, timeout: 15), true)
        XCTAssertTrue(app.navigationBars.staticTexts["Ada Lovelace"].waitForExistence(timeout: 15))
    }

    @MainActor func testTappingANotificationWhileCrewIsOpenOpensItsChat() {
        let app = launch(notifyAfter: 2)
        tapInNotificationCenter(after: 4)
        assertChatOpens(in: app)
    }

    @MainActor func testTappingANotificationInTheBackgroundOpensItsChat() {
        let app = launch(notifyAfter: 2)
        XCUIDevice.shared.press(.home)
        tapInNotificationCenter(after: 4)
        assertChatOpens(in: app)
    }

    @MainActor func testTappingANotificationAfterCrewQuitLaunchesIt() {
        let app = launch(notifyAfter: 2)
        app.terminate()
        tapInNotificationCenter(after: 4)
        XCTAssertEqual(app.wait(for: .runningForeground, timeout: 15), true)
        XCTAssertTrue(app.staticTexts["Sign in to your Hermes server."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.wait(for: .notRunning, timeout: 3))
    }
}
