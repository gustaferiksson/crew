import XCTest

final class ComposerCaretUITests: XCTestCase {
    @MainActor private func launch(_ extra: [String] = []) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "composer-running", "-uiTest", "YES", "-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", "Light", "-server", "hermes.example.com", "-username", "gustaf"] + extra
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        let field = window.textFields.firstMatch.waitForExistence(timeout: 10) ? window.textFields.firstMatch : window.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        return (app, field)
    }

    @MainActor private func moveLeft(_ count: Int, in field: XCUIElement) {
        for _ in 0..<count { field.typeKey(.leftArrow, modifierFlags: []) }
    }

    @MainActor private func expectValue(_ text: String, of field: XCUIElement, _ message: String) {
        let deadline = Date.now.addingTimeInterval(5)
        while field.value as? String != text, Date.now < deadline { RunLoop.current.run(until: .now + 0.2) }
        XCTAssertEqual(field.value as? String, text, message)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testTheCaretStaysPutWhenTheTurnFinishes() {
        let (app, field) = launch(["-finishTurnAfterDraft", "Use the staging context"])
        field.typeText("Use the context")
        moveLeft(7, in: field)
        field.typeText("staging ")
        XCTAssertTrue(app.staticTexts["Deployed to staging."].waitForExistence(timeout: 10) || app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Deployed to staging.")).firstMatch.waitForExistence(timeout: 1), "the turn finished")
        XCTAssertTrue(app.buttons.matching(identifier: "Stop").firstMatch.waitForNonExistence(timeout: 5), "the composer left the running state")
        expectValue("Use the staging context", of: field, "the draft survives the turn finishing")
        field.typeText("X")
        attach(app, "caret-after-finish")
        expectValue("Use the staging Xcontext", of: field, "typing continues at the caret after the turn finishes")
    }

    @MainActor func testShiftReturnInsertsALineAtTheCaret() {
        let (_, field) = launch()
        field.typeText("Use the context")
        moveLeft(7, in: field)
        field.typeKey(.return, modifierFlags: .shift)
        field.typeText("staging")
        expectValue("Use the \nstagingcontext", of: field, "Shift+Return inserts a line at the caret instead of sending")
    }
}
