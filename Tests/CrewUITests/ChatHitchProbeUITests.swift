import XCTest

final class ChatHitchProbeUITests: XCTestCase {
    private let history = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.long-replies.history.json").path

    @MainActor func testScrollHitchesOnALongChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-snapshot", "composer-line", "-server", "hermes.example.com", "-username", "gustaf", "-historyFile", history, "-historyCopies", "14"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        RunLoop.current.run(until: .now.addingTimeInterval(2))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollDraggingMetric, XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            for _ in 0..<3 { top.press(forDuration: 0.01, thenDragTo: bottom, withVelocity: .fast, thenHoldForDuration: 0) }
            for _ in 0..<3 { bottom.press(forDuration: 0.01, thenDragTo: top, withVelocity: .fast, thenHoldForDuration: 0) }
        }
    }
}
