import XCTest

private let titles = ["MJÙKA Idun · Brown", "MJÙKA Thurid · Brown", "MJÙKA Astrid · Chestnut", "HAIKA Sandefjord · Brown"]

final class CarouselUITests: XCTestCase {
    @MainActor func testSwipingThroughTheSlipperCarouselShowsEveryItemWithoutFightingTheTranscript() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "chat-a2ui-carousel", "-server", "hermes.example.com", "-username", "gustaf"]
        app.launch()

        let tiles = titles.enumerated().map { index, title in
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label ENDSWITH %@", title, "\(index + 1) of \(titles.count)")).firstMatch
        }
        XCTAssertTrue(tiles[0].waitForExistence(timeout: 10), "first tile missing:\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "#")).firstMatch.exists)
        let screen = app.windows.firstMatch.frame
        let current = { tiles.lastIndex { $0.exists && $0.frame.minX >= screen.minX && $0.frame.maxX <= screen.maxX } }
        let photo = { (tile: XCUIElement) in tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)) }
        XCTAssertEqual(current(), 0)

        var seen: Set<Int> = [0]
        for _ in 0..<8 {
            guard let index = current(), index < titles.count - 1 else { break }
            let start = photo(tiles[index])
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -220, dy: 0)))
            if let landed = current() { seen.insert(landed) }
        }
        XCTAssertEqual(seen, Set(titles.indices), "every item should be reachable by swiping")
        XCTAssertEqual(current(), titles.count - 1, "the last tile should settle fully visible")

        let header = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Brown sheepskin slippers")).firstMatch
        XCTAssertTrue(header.exists)
        let headerY = header.frame.minY
        let start = photo(tiles[titles.count - 1])
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)))
        XCTAssertGreaterThan(header.frame.minY, headerY + 40, "a vertical drag on the carousel should scroll the transcript")
        XCTAssertEqual(current(), titles.count - 1, "a vertical drag should not page the carousel")
    }
}
