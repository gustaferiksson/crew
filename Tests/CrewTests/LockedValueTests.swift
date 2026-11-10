import AppKit
import SwiftUI
import Testing

private struct ComposerOnly: View {
    @State var draft = "Hi"
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            Spacer()
            Composer(botName: "Hermes", phase: .idle, draft: $draft, isFocused: $isFocused, tray: AttachmentTray(), mentionable: [], features: [], completePath: { _ in [] }, transcribe: { _ in "" }, send: { _ in }, stop: {})
        }
    }
}

private struct ScrolledTranscript: View {
    let barHeight: CGFloat
    @State private var position = ScrollPosition()

    var body: some View {
        TranscriptScroll(position: $position, revision: 0, barHeight: barHeight) {
            LazyVStack {
                ForEach(0..<600) { Text("Row \($0)").frame(height: 40) }
            }
            .scrollTargetLayout()
        }
        .safeAreaBar(edge: .bottom) { Color.gray.frame(height: barHeight) }
    }
}

@MainActor private func views(in view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { views(in: $0) }
}

@MainActor private func rounded(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
}

@MainActor struct LockedValueTests {
    @Test func theMacComposerFieldIs36PointsTall16FromTheSidesAnd8AboveTheBottom() throws {
        let window = OffscreenWindow(size: NSSize(width: 600, height: 300), styleMask: [.borderless])
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: ComposerOnly())
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(1)
        let content = try #require(window.contentView)
        let text = try #require(views(in: content).first { $0 is NSTextField })
        let capsule = try #require(sequence(first: text, next: \.superview).first { $0.bounds.height > text.bounds.height + 1 })
        let field = rounded(capsule.convert(capsule.bounds, to: nil))
        #expect(field.height == 36, "field \(field)")
        #expect(field.minX == 16, "field \(field)")
        #expect(field.minY == 8, "field \(field)")
    }

    @Test func jumpToLatestSits12PointsAboveTheComposerBar() throws {
        let window = OffscreenWindow(size: NSSize(width: 600, height: 700), styleMask: [.titled, .resizable])
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: ScrolledTranscript(barHeight: 60))
        window.setContentSize(NSSize(width: 600, height: 700))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(1)
        let content = try #require(window.contentView)
        userScroll(try #require(scrollView(in: content)), by: 20_000)
        settle(1)
        let arrow = try #require(views(in: content).first { "\(type(of: $0))" == "_FocusRingView" })
        let frame = rounded(arrow.convert(arrow.bounds, to: nil))
        #expect(frame.minY - 60 == 12, "arrow \(frame) over a 60 pt bar")
    }
}
