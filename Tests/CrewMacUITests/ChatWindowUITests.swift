import XCTest

final class ChatWindowUITests: XCTestCase {
    private let atlasPreview = "Tuesday's standup notes are filed."
    private let ledgerPreview = "Q3 numbers reconciled against the bank export."
    private let quillPreview = "Draft two is ready for review."

    @MainActor private func launch(_ extra: [String] = [], appearance: String = "Light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "layout", "-uiTest", "YES", "-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", appearance, "-server", "hermes.example.com", "-username", "gustaf"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts[atlasPreview].waitForExistence(timeout: 20))
        return app
    }

    @MainActor private func chatWindow(in app: XCUIApplication) -> XCUIElement? {
        app.windows.allElementsBoundByIndex.first { !$0.staticTexts[atlasPreview].exists }
    }

    @MainActor private func expectWindows(_ count: Int, in app: XCUIApplication, _ message: String) {
        let deadline = Date.now.addingTimeInterval(10)
        while app.windows.count != count, Date.now < deadline { RunLoop.current.run(until: .now + 0.2) }
        XCTAssertEqual(app.windows.count, count, message)
    }

    @MainActor private func composer(in window: XCUIElement) -> XCUIElement {
        window.textFields.firstMatch.exists ? window.textFields.firstMatch : window.textViews.firstMatch
    }

    @MainActor private func attach(_ window: XCUIElement, _ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testDoubleClickOpensOneWindowPerBotSharingTheDraft() {
        let app = launch()
        XCTAssertEqual(app.windows.count, 1)

        app.staticTexts[atlasPreview].doubleClick()
        expectWindows(2, in: app, "a double-click opens the bot's chat in its own window")

        app.staticTexts[atlasPreview].doubleClick()
        expectWindows(2, in: app, "a second double-click focuses the open window instead of opening another")

        guard let window = chatWindow(in: app) else { return XCTFail("no chat window") }
        let field = composer(in: window)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Move standup to 10")
        guard let main = app.windows.allElementsBoundByIndex.first(where: { $0.staticTexts[atlasPreview].exists }) else { return XCTFail("no main window") }
        let sharedDraft = NSPredicate(format: "value == %@", "Move standup to 10")
        XCTAssertTrue(
            main.textFields.matching(sharedDraft).firstMatch.waitForExistence(timeout: 5) || main.textViews.matching(sharedDraft).firstMatch.exists,
            "both windows edit the same draft"
        )
        XCTAssertEqual(window.title, "Atlas", "the window is titled with the bot")
        attach(window, "chat-window-light")
    }

    @MainActor func testContextMenuOpensTheBotInANewWindow() {
        let app = launch()
        app.staticTexts[ledgerPreview].rightClick()
        XCTAssertTrue(app.menuItems["Open in New Window"].firstMatch.waitForExistence(timeout: 5))
        guard let open = app.menuItems.matching(identifier: "Open in New Window").allElementsBoundByIndex.first(where: \.isHittable) else { return XCTFail("no context menu item") }
        open.click()
        expectWindows(2, in: app, "the context menu opens the bot's window")
    }

    @MainActor func testDoubleClickOnAFavouriteTileOpensItsWindow() {
        let app = launch()
        let tile = app.buttons["Scout, Travel Planner"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        let deadline = Date.now.addingTimeInterval(10)
        var previous = CGRect.null
        while Date.now < deadline, !(tile.isHittable && tile.frame == previous) {
            previous = tile.frame
            RunLoop.current.run(until: .now + 0.2)
        }
        XCTAssertTrue(tile.isHittable, "the favourite tile settles before the double-click")
        tile.doubleClick()
        expectWindows(2, in: app, "a double-click on a favourite tile opens its window")
    }

    @MainActor func testCommandOOpensTheSelectedBotAndCommandWClosesIt() {
        let app = launch()
        app.staticTexts[quillPreview].click()
        app.typeKey("o", modifierFlags: .command)
        expectWindows(2, in: app, "File > Open in New Window opens the selected bot")

        app.typeKey("w", modifierFlags: .command)
        expectWindows(1, in: app, "Cmd-W closes the front chat window")
    }

    @MainActor func testChatWindowInDark() {
        let app = launch(appearance: "Dark")
        app.staticTexts[atlasPreview].doubleClick()
        expectWindows(2, in: app, "a double-click opens the bot's chat in its own window")
        guard let window = chatWindow(in: app) else { return XCTFail("no chat window") }
        attach(window, "chat-window-dark")
    }

    @MainActor func testSignOutClosesChatWindowsAndShowsSignIn() {
        let app = launch(["-signOutAfterChatWindow", "YES"])
        app.staticTexts[atlasPreview].doubleClick()
        expectWindows(2, in: app, "a double-click opens the bot's chat in its own window")
        guard let main = app.windows.allElementsBoundByIndex.first(where: { $0.staticTexts[atlasPreview].exists }) else { return XCTFail("no main window") }
        main.buttons[XCUIIdentifierCloseWindow].click()
        expectWindows(1, in: app, "closing the main window leaves the chat window open")

        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10), "signing out brings back the main window with the sign-in screen")
        expectWindows(1, in: app, "signing out closes every chat window")
    }
}
