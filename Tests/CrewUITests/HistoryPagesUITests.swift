import XCTest

final class HistoryPagesUITests: TranscriptUITestCase {
    @MainActor private func launchPaged() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "composer-line", "-server", "hermes.example.com", "-username", "gustaf", "-historyFile", history, "-historyCopies", "14", "-historyPages", "YES", "-pageDelay", "5000"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        assertRightAboveTheComposer(lastBlock, in: app, "opened")
        return app
    }

    @MainActor private func state(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["history-state"].value as? String ?? ""
    }

    @MainActor private func flingUp(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)), withVelocity: .fast, thenHoldForDuration: 0)
    }

    @MainActor private func reading(_ app: XCUIApplication) -> (label: String, top: CGFloat)? {
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = app.buttons["Attach"].frame.minY
        return app.staticTexts.allElementsBoundByIndex
            .map { ($0.label, $0.frame) }
            .filter { !$0.0.isEmpty && $0.1.minY >= top && $0.1.maxY <= bottom }
            .min { $0.1.minY < $1.1.minY }
            .map { ($0.0, $0.1.minY) }
    }

    @MainActor private func drift(of before: (label: String, top: CGFloat), in app: XCUIApplication) -> CGFloat {
        app.staticTexts.matching(NSPredicate(format: "label == %@", before.label)).allElementsBoundByIndex
            .map { $0.frame.minY - before.top }
            .min { abs($0) < abs($1) } ?? .infinity
    }

    @MainActor private func assertAnOlderPageKeepsTheReader(extraFlings: Int, _ name: String) throws {
        let app = launchPaged()
        XCTAssertEqual(state(app), "more")
        for _ in 0..<40 where state(app) != "loading" { flingUp(app) }
        XCTAssertEqual(state(app), "loading", "scrolling up never loaded an earlier page")
        for _ in 0..<extraFlings { flingUp(app) }
        wait(1.5)
        let before = try XCTUnwrap(reading(app))
        shoot("\(name) while loading", in: app)
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "loading"), object: app.descendants(matching: .any)["history-state"])
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 10), .completed)
        wait(1)
        shoot("\(name) after the page landed", in: app)
        let moved = drift(of: before, in: app)
        print("PAGES \(name) drift \(moved) at \(before.top)")
        XCTAssertEqual(moved, 0, accuracy: 1, "\(name): the row being read moved")
    }

    @MainActor func testAnOlderPageLandingAboveTheReaderLeavesThemInPlace() throws {
        try assertAnOlderPageKeepsTheReader(extraFlings: 0, "near the top")
    }

    @MainActor func testAnOlderPageLandingAtTheTopLeavesTheReaderInPlace() throws {
        try assertAnOlderPageKeepsTheReader(extraFlings: 3, "at the top")
    }
}
