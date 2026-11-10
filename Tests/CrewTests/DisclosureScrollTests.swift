import AppKit
import SwiftUI
import Testing

private let scout = Bot(name: "scout", displayName: "Scout", description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

@MainActor private final class EndDistances {
    var values: [CGFloat] = []
}

private struct HostedChat: View {
    let transcript: Transcript
    let distances: EndDistances
    @State private var draft = ""
    @State private var tray = AttachmentTray()

    var body: some View {
        ChatView(botName: "crew-test", avatar: EmptyView(), transcript: transcript, emptyState: EmptyView(), mentionable: [], draft: $draft, tray: tray)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height - $0.visibleRect.maxY + $0.contentInsets.bottom } action: { distances.values.append($1) }
    }
}

private func exchanges(after count: Int) -> Transcript {
    let start = Date.now.addingTimeInterval(-3 * 3600)
    let earlier = (0..<count).map { index in
        Turn(id: "u\(index)", prompt: Prompt(text: "Question \(index) about the trip?", sentAt: start.addingTimeInterval(Double(index) * 60)), reply: String(repeating: "A reply that wraps across the column a few times. ", count: 1 + (index * 7) % 40), status: .complete, startedAt: start.addingTimeInterval(Double(index) * 60), finishedAt: start.addingTimeInterval(Double(index) * 60 + 5))
    }
    let messages = (0..<2).map { index in
        let at = start.addingTimeInterval(3 * 3600 - 600 + Double(index) * 60)
        return Turn(
            id: "m\(index)",
            agentMessage: AgentMessage("Message from 🤖 Scout (@scout): \(String(repeating: "Can you add the Lofoten ferry to the trip notes? ", count: 3))"),
            work: [WorkItem(id: "m\(index)-w0", kind: .tool(ToolCall(name: "message_agent", subject: "scout", arguments: #"{"target": "scout"}"#, status: .success)), startedAt: at.addingTimeInterval(2), duration: 1)],
            reply: "Added the 08:15 ferry to the trip notes.",
            status: .complete,
            startedAt: at,
            finishedAt: at.addingTimeInterval(4)
        )
    }
    return Transcript(turns: earlier + messages).visible
}

@MainActor struct DisclosureScrollTests {
    @Test func theLastExchangeOpensAndClosesWithTheEndHeld() throws {
        let distances = EndDistances()
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: HostedChat(transcript: exchanges(after: 200), distances: distances).environment(BotStore(fixture: [scout], statuses: [:])).environment(ChatPins(fileURL: nil)))
        window.setContentSize(NSSize(width: 700, height: 800))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(1)

        let scroll = try #require(window.contentView.flatMap(scrollView(in:)))
        let height = { scroll.documentView?.frame.height ?? 0 }
        let collapsed = height()
        let header = stride(from: CGFloat(40), to: 200, by: 4).first { y in
            click(window, at: NSPoint(x: 60, y: y))
            settle(0.5)
            return height() - collapsed > 70
        }
        let y = try #require(header, "no click opened the last exchange")
        let growth = height() - collapsed
        for (step, point) in [("collapse", y + growth), ("expand", y), ("collapse", y + growth)] {
            let before = height()
            distances.values = []
            click(window, at: NSPoint(x: 60, y: point))
            settle(1)
            let worst = distances.values.max() ?? 0
            print("Disclosure: \(step) height \(before) -> \(height()), \(distances.values.count) geometry changes, farthest from the end \(worst)")
            #expect(abs(abs(height() - before) - growth) < 1, "\(step) missed the header: height \(before) -> \(height())")
            #expect(worst < 1, "\(step) left the end by \(worst) pt during the animation")
            #expect(distances.values.count < 10, "\(step) changed the scroll geometry \(distances.values.count) times")
        }
    }
}
