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
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("A double-click that also changes the List selection sometimes opens no window on macOS 27 (#90)", options: options) {
            expectWindows(2, in: app, "a double-click on an unselected row opens the bot's chat in its own window")
        }
        if app.windows.count == 1 {
            app.staticTexts[atlasPreview].doubleClick()
            expectWindows(2, in: app, "a double-click on the selected row opens the bot's chat in its own window")
        }

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

    @MainActor func testCommandOOpensTheSelectedBotAndCommandWClosesIt() {
        let app = launch()
        app.staticTexts[quillPreview].click()
        app.typeKey("o", modifierFlags: .command)
        expectWindows(2, in: app, "File > Open in New Window opens the selected bot")

        app.typeKey("w", modifierFlags: .command)
        expectWindows(1, in: app, "Cmd-W closes the front chat window")
    }

    @MainActor func testSignOutClosesChatWindowsAndShowsSignIn() {
        let app = launch(["-signOutAfterChatWindow", "YES"])
        app.staticTexts[atlasPreview].click()
        let atlasComposer = NSPredicate(format: "placeholderValue == %@ OR label == %@", "Message Atlas", "Message Atlas")
        XCTAssertTrue(
            app.textFields.matching(atlasComposer).firstMatch.waitForExistence(timeout: 10) || app.textViews.matching(atlasComposer).firstMatch.exists,
            "a click selects the bot"
        )
        app.staticTexts[atlasPreview].doubleClick()
        expectWindows(2, in: app, "a double-click opens the bot's chat in its own window")
        guard let main = app.windows.allElementsBoundByIndex.first(where: { $0.staticTexts[atlasPreview].exists }) else { return XCTFail("no main window") }
        main.buttons[XCUIIdentifierCloseWindow].click()
        expectWindows(1, in: app, "closing the main window leaves the chat window open")

        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10), "signing out brings back the main window with the sign-in screen")
        expectWindows(1, in: app, "signing out closes every chat window")
    }
}
