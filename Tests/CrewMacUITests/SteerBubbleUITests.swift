import XCTest

final class SteerBubbleUITests: XCTestCase {
    @MainActor private func attach(_ element: XCUIElement, _ name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testATakenSteerKeepsItsTextVisibleInTheBubble() {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-snapshot", "composer-running", "-uiTest", "YES", "-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", appearance, "-server", "hermes.example.com", "-username", "gustaf"]
            app.launch()
            let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 20))
            let text = "Sounds worth a try, go ahead and order it if the shop looks legit and the delivery is cheap"
            field.click()
            field.typeText(text)
            XCTAssertEqual(field.value as? String, text, "the composer holds the typed steer (\(appearance))")
            field.typeKey(.return, modifierFlags: [])
            let bubble = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", text, text)).firstMatch
            XCTAssertTrue(app.staticTexts["Waiting"].waitForExistence(timeout: 10))
            attach(app.windows.firstMatch, "waiting-\(appearance.lowercased())")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "waiting-tree-\(appearance.lowercased())"
            tree.lifetime = .keepAlways
            add(tree)
            XCTAssertTrue(bubble.waitForExistence(timeout: 5), "the waiting steer has a bubble (\(appearance))")
            XCTAssertTrue(app.staticTexts["Waiting"].waitForNonExistence(timeout: 20))
            attach(app.windows.firstMatch, "taken-\(appearance.lowercased())")
            XCTAssertTrue(bubble.waitForExistence(timeout: 5), "the taken steer has a bubble (\(appearance))")
            guard bubble.exists else { return app.terminate() }
            XCTAssertGreaterThan(bubble.frame.height, 20, "the taken steer's bubble has its text's height (\(appearance))")
            let shot = bubble.screenshot()
            attach(bubble, "taken-bubble-\(appearance.lowercased())")
            guard let image = shot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return XCTFail("no bubble screenshot") }
            XCTAssertGreaterThan(whiteShareInsideBubble(image), 0.03, "the taken steer's text is not drawn white on its bubble (\(appearance))")
            app.terminate()
        }
    }
}
