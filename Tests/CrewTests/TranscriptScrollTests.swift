import AppKit
import SwiftUI
import Testing

@MainActor @Observable private final class ScrollModel {
    var rows: [String] = []
    var barHeight: CGFloat = 60
    var position = ScrollPosition()
    var top: CGFloat = 0
    var distance: CGFloat = 0
    var watched: Int?
    var watchedFrame = CGRect.zero
}

private struct Column: View {
    @Bindable var model: ScrollModel

    var body: some View {
        TranscriptScroll(position: $model.position, revision: model.rows) {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(Array(model.rows.enumerated()), id: \.offset) { index, text in
                    Text(text)
                        .id(index)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { if index == model.watched { model.watchedFrame = $0 } }
                }
            }
            .scrollTargetLayout()
            .padding(16)
        }
        .onScrollGeometryChange(for: [CGFloat].self) { [$0.visibleRect.minY, $0.contentSize.height - $0.visibleRect.maxY + $0.contentInsets.bottom] } action: {
            model.top = $1[0]
            model.distance = $1[1]
        }
        .safeAreaBar(edge: .bottom) {
            Color.gray.frame(height: model.barHeight)
        }
    }
}

private let rows = (0..<300).map { String(repeating: "Row \($0) has a few words that wrap across the column. ", count: 1 + ($0 * 7) % 13) }

@MainActor func settle(_ seconds: Double = 0.4) {
    RunLoop.main.run(until: .now + seconds)
}

@MainActor func scrollView(in view: NSView) -> NSScrollView? {
    view as? NSScrollView ?? view.subviews.lazy.compactMap { scrollView(in: $0) }.first
}

@MainActor func userScroll(_ scroll: NSScrollView, by distance: CGFloat) {
    let steps = 20
    for step in 0...steps {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: step == 0 ? 1 : step == steps ? 4 : 2)
        guard let wheel = NSEvent(cgEvent: event) else { return }
        scroll.scrollWheel(with: wheel)
        if step < steps {
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y - distance / CGFloat(steps)))
            scroll.reflectScrolledClipView(clip)
        }
        RunLoop.main.run(until: .now + 0.016)
    }
    settle()
}

@MainActor struct TranscriptScrollTests {
    private func host(_ model: ScrollModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 600, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: Column(model: model))
        window.setContentSize(NSSize(width: 600, height: 700))
        window.orderBack(nil)
        settle()
        return window
    }

    @Test func theEndStaysInViewWhileTheReaderIsThere() throws {
        let model = ScrollModel()
        let window = host(model)
        defer { window.orderOut(nil) }
        model.rows = rows
        settle(1)
        #expect(abs(model.distance) < 1, "cold open \(model.distance)")
        model.rows[299] += String(repeating: " streaming more text", count: 30)
        settle()
        #expect(abs(model.distance) < 1, "last row grew \(model.distance)")
        model.rows.append("A turn from another client.")
        settle()
        #expect(abs(model.distance) < 1, "row appended \(model.distance)")
        model.barHeight = 200
        settle()
        #expect(abs(model.distance) < 1, "bar grew \(model.distance)")
        model.barHeight = 60
        settle()
        #expect(abs(model.distance) < 1, "bar shrank \(model.distance)")
    }

    @Test func nothingMovesWhatTheReaderIsReading() throws {
        let model = ScrollModel()
        let window = host(model)
        defer { window.orderOut(nil) }
        model.rows = rows
        settle(1)
        let content = try #require(window.contentView)
        let scroll = try #require(scrollView(in: content))
        userScroll(scroll, by: 1500)
        #expect(model.distance > 1400)
        let reading = model.top
        model.rows[model.rows.count - 1] += String(repeating: " streaming while reading", count: 40)
        settle()
        model.rows.append("A turn while reading.")
        settle()
        #expect(abs(model.top - reading) < 1, "moved \(model.top - reading)")

        for _ in 0..<5 where model.distance > 0 { userScroll(scroll, by: -model.distance) }
        model.rows.append("A turn after scrolling back by hand.")
        settle()
        #expect(model.distance < 40, "after a manual return \(model.distance)")

        model.watched = 151
        model.position.scrollTo(id: 150, anchor: .center)
        settle()
        let header = model.watchedFrame.minY
        let top = model.top
        #expect(header > 0 && header < 640, "row 151 at \(model.watchedFrame)")
        model.rows[151] += String(repeating: " expanded work log line", count: 40)
        settle()
        #expect(abs(model.top - top) < 1, "expansion scrolled by \(model.top - top)")
        #expect(abs(model.watchedFrame.minY - header) < 1, "expansion moved its header by \(model.watchedFrame.minY - header)")
    }

    @Test func theAnimatedEdgeJumpLandsAtTheEndAndHandsOver() throws {
        let model = ScrollModel()
        let window = host(model)
        defer { window.orderOut(nil) }
        model.rows = rows
        settle(1)
        let content = try #require(window.contentView)
        let scroll = try #require(scrollView(in: content))
        userScroll(scroll, by: 20_000)
        #expect(model.distance > 19_000)
        withAnimation(.smooth) { model.position.scrollTo(edge: .bottom) }
        for _ in 0..<20 where abs(model.distance) >= 1 || model.position.edge != nil { settle(0.25) }
        #expect(model.position.edge == nil && model.position.viewID(type: String.self) == transcriptEnd, "the edge jump did not hand over to the end")
        #expect(abs(model.distance) < 1, "after the jump \(model.distance)")
        model.rows[model.rows.count - 1] += String(repeating: " streaming after the jump", count: 30)
        settle()
        #expect(abs(model.distance) < 1, "streaming after the jump \(model.distance)")
        model.rows.append("A turn after the jump.")
        settle()
        #expect(abs(model.distance) < 1, "row appended after the jump \(model.distance)")
    }

    @Test func aSearchJumpFromTheEndStaysWhereItLanded() {
        let model = ScrollModel()
        let window = host(model)
        defer { window.orderOut(nil) }
        model.rows = rows
        settle(1)
        #expect(abs(model.distance) < 1)
        model.watched = 150
        model.position.scrollTo(id: 150, anchor: .center)
        settle()
        #expect(model.watchedFrame.minY >= 0 && model.watchedFrame.maxY <= 640, "row 150 at \(model.watchedFrame)")
        model.rows[model.rows.count - 1] += String(repeating: " streaming after the search", count: 30)
        settle()
        #expect(model.watchedFrame.minY >= 0 && model.watchedFrame.maxY <= 640, "row 150 left the screen: \(model.watchedFrame)")
        #expect(model.distance > 10_000)
    }

    @Test func aSearchJumpIntoArrivingRowsShowsTheRow() {
        let model = ScrollModel()
        let window = host(model)
        defer { window.orderOut(nil) }
        model.watched = 40
        model.rows = rows
        model.position.scrollTo(id: 40, anchor: .center)
        settle(1)
        #expect(model.watchedFrame.minY >= 0 && model.watchedFrame.maxY <= 640, "row 40 at \(model.watchedFrame)")
    }
}
