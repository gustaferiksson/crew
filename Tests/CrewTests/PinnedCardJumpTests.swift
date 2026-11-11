import AppKit
import SwiftUI
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

@MainActor @Observable private final class JumpModel {
    var jumps = 0
    var canJump = false
}

private struct GoToPinnedCard: View {
    let model: JumpModel
    @FocusedBinding(\.pinnedCardJumps) private var jumps

    var body: some View {
        Color.clear
            .frame(height: 0)
            .onChange(of: jumps == nil, initial: true) { model.canJump = jumps != nil }
            .onChange(of: model.jumps) { jumps? += 1 }
    }
}

private struct PinnedChat: View {
    let transcript: Transcript
    let presentation: ChatPresentation
    let model: JumpModel
    @State private var draft = Draft()
    @State private var tray = AttachmentTray()

    var body: some View {
        VStack(spacing: 0) {
            ChatView(botName: "crew-test", avatar: EmptyView(), transcript: transcript, emptyState: EmptyView(), mentionable: [], draft: draft, tray: tray, pinKey: "crew-test", presentation: presentation)
            GoToPinnedCard(model: model)
        }
    }
}

private final class KeyWindow: OffscreenWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor private func scrollViews(in view: NSView) -> [NSScrollView] {
    [view as? NSScrollView].compactMap(\.self) + view.subviews.flatMap(scrollViews(in:))
}

@MainActor @Suite(.serialized) struct PinnedCardJumpTests {
    private func cardChat(prose: Int, after: Int) throws -> (Transcript, String) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode(HistoryFile.self, from: Data(contentsOf: fixtures.appending(path: "chat.a2ui-update.history.json"))).messages
        let card = try #require(Transcript(history: rows).turns.first?.reply)
        let store = SurfaceStore()
        store.sync(Transcript(turns: [Turn(id: "probe", prompt: nil, reply: card, status: .complete, startedAt: .now, finishedAt: .now)]))
        let surface = try #require(store.newest?.surface)
        let start = Date.now.addingTimeInterval(-3600)
        let turn = { (id: String, index: Int, reply: String) in
            Turn(id: id, prompt: Prompt(text: "Question \(index)?", sentAt: start.addingTimeInterval(Double(index) * 10)), reply: reply, status: .complete, startedAt: start.addingTimeInterval(Double(index) * 10), finishedAt: start.addingTimeInterval(Double(index) * 10 + 5))
        }
        let filler = String(repeating: "A reply that wraps across the column a few times. ", count: 12)
        let intro = (0..<prose).map { "Paragraph \($0) of the long introduction before the card, long enough to wrap." }.joined(separator: "\n\n")
        let turns = (0..<40).map { turn("b\($0)", $0, filler) } + [turn("card", 40, intro + "\n\n" + card)] + (0..<after).map { turn("a\($0)", 41 + $0, filler) }
        return (Transcript(turns: turns), surface)
    }

    @Test(arguments: [(40, 20), (0, 0)])
    func goingToThePinnedCardScrollsToItsTurnAndStaysThere(prose: Int, after: Int) throws {
        let (transcript, surface) = try cardChat(prose: prose, after: after)
        let pins = ChatPins(fileURL: nil)
        pins.pin(surface, in: "crew-test")
        let model = JumpModel()
        let window = KeyWindow(size: NSSize(width: 700, height: 600), styleMask: [.titled, .resizable])
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: PinnedChat(transcript: transcript, presentation: ChatPresentation(), model: model).environment(BotStore(fixture: [], statuses: [:])).environment(pins))
        window.setContentSize(NSSize(width: 700, height: 600))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(1.5)
        let scroll = try #require(window.contentView.flatMap { scrollViews(in: $0).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) } })
        let fromEnd = { (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom }
        #expect(fromEnd() < 1, "the chat did not open at the end")

        #expect(model.canJump, "View > Go to Pinned Card is disabled")
        model.jumps += 1
        settle(1)
        let landed = scroll.contentView.bounds.minY
        settle(1)
        print("Pinned jump prose \(prose): landed at \(landed), \(fromEnd()) pt from the end")
        #expect(abs(scroll.contentView.bounds.minY - landed) < 1, "the jump moved \(scroll.contentView.bounds.minY - landed) pt within 1 s")
        #expect(fromEnd() > 300, "the jump left the reader at the end, or an end hold pulled it back")
    }
}
