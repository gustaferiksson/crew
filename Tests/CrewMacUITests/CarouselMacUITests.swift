import XCTest

final class CarouselMacUITests: XCTestCase {
    @MainActor private func launch(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-a2ui-carousel", "-uiTest", "YES", "-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", appearance, "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()
        return app
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        RunLoop.current.run(until: .now + 4)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testHoverArrowsPageTheCarousel() {
        let app = launch(appearance: "Light")
        let tile = { (position: Int) in
            app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", "\(position) of 4")).firstMatch
        }
        XCTAssertTrue(tile(1).waitForExistence(timeout: 20), app.debugDescription)
        let restingX = tile(1).frame.minX
        attach(app, "macos-chat-a2ui-carousel")

        tile(1).hover()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "hovering the carousel should show the Next arrow")
        XCTAssertFalse(app.buttons["Previous"].exists, "no Previous arrow on the first item")
        attach(app, "macos-chat-a2ui-carousel-hover")
        next.click()
        let deadline = Date.now.addingTimeInterval(5)
        while abs(tile(2).frame.minX - restingX) > 4, Date.now < deadline { RunLoop.current.run(until: .now + 0.2) }
        XCTAssertEqual(tile(2).frame.minX, restingX, accuracy: 4, "Next should bring the second item to the leading edge")
        XCTAssertTrue(app.buttons["Previous"].exists)
        app.terminate()

        let dark = launch(appearance: "Dark")
        XCTAssertTrue(dark.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", "1 of 4")).firstMatch.waitForExistence(timeout: 20))
        attach(dark, "macos-chat-a2ui-carousel-dark")
    }
}
