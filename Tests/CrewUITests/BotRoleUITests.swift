import XCTest

final class BotRoleUITests: XCTestCase {
    @MainActor func testRolesShowInRowsAndTilesAndMatchSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "sidebar", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let forge = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Forge, Release Engineer")).firstMatch
        XCTAssertTrue(forge.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Ada Lovelace, Head of Research and Analytics")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", "Scout, Travel Planner", "Working")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Atlas,")).firstMatch.exists)

        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("release")
        XCTAssertTrue(forge.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Ledger")).firstMatch.exists)
    }
}
