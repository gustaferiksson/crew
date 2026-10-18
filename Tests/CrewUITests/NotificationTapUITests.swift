import XCTest

final class NotificationTapUITests: XCTestCase {
    @MainActor private func launch(notifyAfter seconds: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "sidebar", "-server", "hermes.example.com", "-username", "gustaf", "-uiTest", "YES", "-notifyProfile", "ada", "-notifyAfter", "\(seconds)"]
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            guard alert.buttons["Allow"].exists else { return false }
            alert.buttons["Allow"].tap()
            return true
        }
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        return app
    }

    @MainActor private func tapBanner() {
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Done with the migration dry run.")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 60))
        banner.tap()
    }

    @MainActor private func assertChatOpens(in app: XCUIApplication) {
        XCTAssertEqual(app.wait(for: .runningForeground, timeout: 15), true)
        XCTAssertTrue(app.navigationBars.staticTexts["Ada Lovelace"].waitForExistence(timeout: 15))
    }

    @MainActor func testTappingANotificationWhileCrewIsOpenOpensItsChat() {
        let app = launch(notifyAfter: 6)
        tapBanner()
        assertChatOpens(in: app)
    }

    @MainActor func testTappingANotificationInTheBackgroundOpensItsChat() {
        let app = launch(notifyAfter: 8)
        XCUIDevice.shared.press(.home)
        tapBanner()
        assertChatOpens(in: app)
    }

    @MainActor func testTappingANotificationAfterCrewQuitLaunchesIt() {
        let app = launch(notifyAfter: 12)
        app.terminate()
        tapBanner()
        XCTAssertEqual(app.wait(for: .runningForeground, timeout: 15), true)
        XCTAssertTrue(app.staticTexts["Sign in to your Hermes server."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.wait(for: .notRunning, timeout: 3))
    }
}
