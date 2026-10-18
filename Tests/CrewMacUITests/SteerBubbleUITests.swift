import XCTest

final class SteerBubbleUITests: XCTestCase {
    @MainActor func testATakenSteerKeepsItsTextVisibleInTheBubble() {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-snapshot", "composer-running", "-uiTest", "YES", "-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", appearance, "-server", "hermes.example.com", "-username", "gustaf"]
            app.launch()
            let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 20))
            let text = "Sounds worth a try, go ahead and order it if the shop looks legit and the delivery is cheap :)"
            field.click()
            field.typeText(text)
            app.buttons["Steer"].click()
            XCTAssertTrue(app.staticTexts["Waiting"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Waiting"].waitForNonExistence(timeout: 20))
            let bubble = app.staticTexts[text]
            XCTAssertTrue(bubble.waitForExistence(timeout: 5))
            RunLoop.current.run(until: .now + 1)
            let shot = bubble.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "taken-steer-\(appearance.lowercased())"
            attachment.lifetime = .keepAlways
            add(attachment)
            guard let image = shot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return XCTFail("no bubble screenshot") }
            XCTAssertGreaterThan(whiteShareInsideBubble(image), 0.03, "the taken steer's text is not drawn white on its bubble (\(appearance))")
            app.terminate()
        }
    }
}
