import AppKit
import SwiftUI
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private struct ResizingChat: View {
    let transcript: Transcript
    @State private var draft = ""
    @State private var tray = AttachmentTray()

    var body: some View {
        NavigationSplitView {
            List(0..<5, id: \.self) { Text("Bot \($0)") }
        } detail: {
            NavigationStack {
                ChatView(botName: "crew-test", avatar: EmptyView(), transcript: transcript, emptyState: EmptyView(), mentionable: [], draft: $draft, tray: tray)
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 640)
        }
        .inspector(isPresented: .constant(false)) {
            Text("Inspector")
                .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
        }
    }
}

@MainActor struct InspectorToggleTests {
    @Test func theInspectorAnimationDoesNotRebuildTheTranscriptRowsOnEveryFrame() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode(HistoryFile.self, from: Data(contentsOf: fixtures.appending(path: "chat.agent-messages.history.json"))).messages
        let root = ResizingChat(transcript: Transcript(history: rows).visible)
            .environment(BotStore(fixture: [crewTest], statuses: [:]))
            .environment(ChatPins(fileURL: nil))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1400, height: 900), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 1400, height: 900))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(1.5)

        let steps = 20
        TurnView.bodies = 0
        for step in 1...steps {
            window.setContentSize(NSSize(width: 1400 - 17 * step, height: 900))
            RunLoop.main.run(until: .now)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        print("InspectorToggle: \(TurnView.bodies) TurnView bodies over \(steps) width steps")
        #expect(TurnView.bodies <= 5 * steps, "a narrower chat column should reflow the visible rows, not rebuild them")
    }
}
