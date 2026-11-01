import AppKit
import SwiftUI
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private struct LiveChat: View {
    let session: ChatSession
    @State private var draft = ""
    @State private var tray = AttachmentTray()

    var body: some View {
        ChatView(botName: "crew-test", avatar: EmptyView(), transcript: session.transcript.visible, emptyState: EmptyView(), mentionable: [], draft: $draft, tray: tray, actions: ChatActions(stop: { session.stop() }, retry: { _ in session.stop() }, unqueue: { _ in session.stop() }))
    }
}

@MainActor struct StreamingRenderTests {
    @Test func aStreamedTokenRedrawsOnlyTheStreamingTurn() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var transcript = Transcript(history: try decoder.decode(HistoryFile.self, from: Data(contentsOf: fixtures.appending(path: "chat.long-replies.history.json"))).messages)
        transcript.begin(prompt: "Run step one, then tell me what you found.")
        let events = try String(contentsOf: fixtures.appending(path: "chat.steer-answer-after-tools-turn.jsonl"), encoding: .utf8).split(separator: "\n")
            .map { try JSONDecoder().decode(GatewayEvent.self, from: Data($0.utf8)) }
        let session = ChatSession(fixture: crewTest, transcript: transcript, todos: [])
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 1600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: LiveChat(session: session).environment(BotStore(fixture: [crewTest], statuses: [:])).environment(ChatPins(fileURL: nil)))
        window.setContentSize(NSSize(width: 700, height: 1600))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(1)

        let realized = TurnView.bodies
        var tokens = 0
        var bodies = 0
        var elapsed = Duration.zero
        let clock = ContinuousClock()
        for event in events {
            TurnView.bodies = 0
            let start = clock.now
            session.apply(event)
            RunLoop.main.run(until: .now)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let spent = clock.now - start
            settle(0.01)
            guard event.type == "message.delta" else { continue }
            elapsed += spent
            bodies += TurnView.bodies
            tokens += 1
        }
        print("StreamingRender: \(realized) TurnView bodies to open, \(bodies) over \(tokens) tokens, \(elapsed / tokens) per token")
        #expect(tokens > 30)
        #expect(bodies <= tokens, "each token should redraw only the streaming turn")
    }
}
