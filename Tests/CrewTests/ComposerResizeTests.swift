import AppKit
import SwiftUI
import Testing

nonisolated enum ResizedWindow: CaseIterable, Sendable {
    case main, chat
}

private struct ChatColumn: View {
    @State var draft: String
    @State private var isAtBottom = true
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(0..<40) { index in
                            Text(String(repeating: "Reply \(index) wraps when the column gets narrower. ", count: 3))
                        }
                    }
                    .padding(16)
                    Color.clear
                        .frame(height: 0)
                        .id("bottom")
                }
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentSize.height - $0.visibleRect.maxY + $0.contentInsets.bottom, $0.contentInsets.bottom] } action: { old, new in
                isAtBottom = new[0] < 40
                if new[1] > old[1], old[0] < 40 { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaBar(edge: .bottom) {
                Composer(botName: "Hermes", phase: .idle, draft: $draft, isFocused: $isFocused, tray: AttachmentTray(), mentionable: [], completePath: { _ in [] }, transcribe: { _ in "" }, send: { _ in }, stop: {})
                    .modifier(JumpToLatest(isAtBottom: isAtBottom) {})
            }
        }
    }
}

private struct ResizingWindow: View {
    let window: ResizedWindow
    let draft: String
    @State private var selection: Int? = 0

    var body: some View {
        if window == .chat {
            NavigationStack { ChatColumn(draft: draft) }
                .frame(minWidth: 320)
                .inspector(isPresented: .constant(false)) {
                    Text("Inspector")
                        .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
                }
        } else {
            mainWindow
        }
    }

    private var mainWindow: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(0..<5) { Text("Bot \($0)").tag($0) }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 400)
        } detail: {
            NavigationStack { ChatColumn(draft: draft) }
                .navigationSplitViewColumnWidth(min: 320, ideal: 640)
        }
        .inspector(isPresented: .constant(false)) {
            Text("Inspector")
                .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
        }
    }
}

@MainActor struct ComposerResizeTests {
    private func textField(in view: NSView) -> NSTextField? {
        view as? NSTextField ?? view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    @Test(arguments: ResizedWindow.allCases, ["", "Line one\nLine two\nLine three\nLine four\nLine five\nLine six\nLine seven"])
    func theComposerStaysOnTheBottomEdgeWhileTheWindowResizes(in layout: ResizedWindow, draft: String) throws {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1000, height: 600), styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: ResizingWindow(window: layout, draft: draft))
        window.setContentSize(NSSize(width: 1000, height: 600))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: .now + 0.5)
        let content = try #require(window.contentView)
        let field = try #require(textField(in: content))
        let resting = field.convert(field.bounds, to: nil)

        let shrinking = (1...10).map { NSSize(width: 1000 - $0 * 12, height: 600 - $0 * 9) }
        let growing = (1...10).map { NSSize(width: 880 + $0 * 12, height: 510 + $0 * 9) }
        var drift: [String] = []
        for size in shrinking + growing {
            window.setContentSize(size)
            content.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let end = Date.now + 0.05
            while Date.now < end {
                RunLoop.main.run(mode: .default, before: .now + 0.005)
                let frame = field.convert(field.bounds, to: nil)
                if abs(frame.minY - resting.minY) > 0.5 || abs(frame.height - resting.height) > 0.5 {
                    drift.append("\(Int(size.width))x\(Int(size.height)): y \(Int(frame.minY)) h \(Int(frame.height))")
                }
            }
        }
        #expect(drift.isEmpty, "resting y \(Int(resting.minY)) h \(Int(resting.height)); \(drift.count) samples off, first: \(drift.prefix(5).joined(separator: "; "))")
    }
}
