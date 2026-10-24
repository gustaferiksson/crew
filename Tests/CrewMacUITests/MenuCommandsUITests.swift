import XCTest

final class MenuCommandsUITests: XCTestCase {
    private let atlasPreview = "Tuesday's standup notes are filed."

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "layout", "-uiTest", "YES", "-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", "Light", "-server", "hermes.example.com", "-username", "gustaf", "-settingsPane", "account"]
        app.launch()
        XCTAssertTrue(app.staticTexts[atlasPreview].waitForExistence(timeout: 20))
        return app
    }

    @MainActor private func menuItem(_ title: String, in menu: String, of app: XCUIApplication) -> XCUIElement {
        app.menuBars.menuBarItems[menu].click()
        return app.menuBars.menuItems[title]
    }

    @MainActor private func attach(_ element: XCUIElement, _ name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testNewBotIsAFileCommandThatShowsTheSheetInTheMainWindowFromAnyWindow() {
        let app = launch()
        let accountMenu = app.windows.firstMatch.descendants(matching: .any).matching(NSPredicate(format: "label == 'Account'")).firstMatch
        XCTAssertFalse(accountMenu.exists, "the Mac toolbar has no Account menu")

        let newBot = menuItem("New Bot…", in: "File", of: app)
        XCTAssertTrue(newBot.waitForExistence(timeout: 5), "File has New Bot…")
        XCTAssertTrue(newBot.isEnabled, "New Bot… is enabled while connected")
        newBot.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5), "File > New Bot… shows the New Bot sheet")
        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertFalse(app.sheets.firstMatch.waitForExistence(timeout: 2))

        app.staticTexts[atlasPreview].doubleClick()
        let deadline = Date.now.addingTimeInterval(10)
        while app.windows.count != 2, Date.now < deadline { RunLoop.current.run(until: .now + 0.2) }
        XCTAssertEqual(app.windows.count, 2, "a double-click opens the bot's chat window")
        app.typeKey("n", modifierFlags: .command)
        guard let main = app.windows.allElementsBoundByIndex.first(where: { $0.staticTexts[atlasPreview].exists }) else { return XCTFail("no main window") }
        XCTAssertTrue(main.sheets.firstMatch.waitForExistence(timeout: 5), "Command-N from a chat window shows the sheet in the main window")
    }

    @MainActor func testViewMenuTogglesTheInspectorAndNamesItsState() {
        let app = launch()
        let show = menuItem("Show Inspector", in: "View", of: app)
        XCTAssertTrue(show.waitForExistence(timeout: 5), "View has Show Inspector")
        XCTAssertTrue(show.isEnabled, "Show Inspector is enabled with a bot selected")
        show.click()

        let hide = menuItem("Hide Inspector", in: "View", of: app)
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "the item reads Hide Inspector while the inspector is open")
        app.typeKey(.escape, modifierFlags: [])
        attach(app.windows.firstMatch, "inspector-open")

        app.typeKey("i", modifierFlags: [.control, .command])
        XCTAssertTrue(menuItem("Show Inspector", in: "View", of: app).waitForExistence(timeout: 5), "Control-Command-I hides it again")
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor func testCommandCommaOpensSettingsWithAccountAndNotifications() {
        let app = launch()
        app.typeKey(",", modifierFlags: .command)
        let account = app.windows["Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 5), "Command-Comma opens Settings on the Account pane")
        XCTAssertTrue(account.staticTexts["hermes.example.com"].exists, "the pane shows the server")
        XCTAssertTrue(account.buttons["Sign Out…"].exists, "Sign Out lives in Settings > Account")
        attach(account, "settings-account")

        account.toolbars.buttons["Notifications"].click()
        let notifications = app.windows["Notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5), "the Notifications pane titles the window")
        XCTAssertTrue(notifications.checkBoxes["Replies"].exists || notifications.switches["Replies"].exists, "the pane holds the notification preferences")
        attach(notifications, "settings-notifications")
    }

    @MainActor func testSignOutFromSettingsClosesChatWindowsAndShowsSignIn() {
        let app = launch()
        app.staticTexts[atlasPreview].doubleClick()
        let opened = Date.now.addingTimeInterval(10)
        while app.windows.count != 2, Date.now < opened { RunLoop.current.run(until: .now + 0.2) }
        XCTAssertEqual(app.windows.count, 2, "a double-click opens the bot's chat window")

        app.typeKey(",", modifierFlags: .command)
        let account = app.windows["Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.buttons["Sign Out…"].click()
        let confirm = app.buttons["Sign Out"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Sign Out asks first")
        confirm.click()

        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 15), "the main window comes back with the sign-in screen")
        XCTAssertTrue(account.staticTexts["Not Signed In"].waitForExistence(timeout: 5), "Settings switches to its signed-out pane")
        let closed = Date.now.addingTimeInterval(10)
        while app.windows.count != 2, Date.now < closed { RunLoop.current.run(until: .now + 0.2) }
        XCTAssertEqual(app.windows.count, 2, "only the main window and Settings stay open")
    }
}
