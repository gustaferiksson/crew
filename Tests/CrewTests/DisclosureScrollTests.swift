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

private let botThreadFile = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/bot-thread/default.history.json")

private func botThread(endingWith last: String) throws -> Transcript {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let thread = Transcript(history: try decoder.decode([HistoryRow].self, from: Data(contentsOf: botThreadFile))).visible.turns
    let end = try #require(thread.lastIndex { last == "to" ? $0.outgoingMessage != nil : $0.agentMessage != nil })
    let start = try #require(thread.first?.startedAt).addingTimeInterval(-200 * 60)
    let earlier = (0..<200).map { index in
        Turn(id: "u\(index)", prompt: Prompt(text: "Question \(index) about the trip?", sentAt: start.addingTimeInterval(Double(index) * 60)), reply: String(repeating: "A reply that wraps across the column a few times. ", count: 1 + (index * 7) % 40), status: .complete, startedAt: start.addingTimeInterval(Double(index) * 60), finishedAt: start.addingTimeInterval(Double(index) * 60 + 5))
    }
    return Transcript(turns: earlier + thread[...end])
}

@MainActor struct DisclosureScrollTests {
    @Test(.serialized, arguments: ["from", "to"])
    func theLastBotMessageRowOpensAndClosesWithTheEndHeld(last: String) throws {
        let distances = EndDistances()
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: HostedChat(transcript: try botThread(endingWith: last), distances: distances).environment(BotStore(fixture: [scout], statuses: [:])).environment(ChatPins(fileURL: nil)))
        window.setContentSize(NSSize(width: 700, height: 800))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(2)

        let scroll = try #require(window.contentView.flatMap(scrollView(in:)))
        let height = { scroll.documentView?.frame.height ?? 0 }
        #expect(abs(distances.values.last ?? 0) < 1, "opened \(distances.values.last ?? 0) pt from the end")
        var growth: CGFloat = 0
        let header = stride(from: CGFloat(40), to: 300, by: 4).first { y in
            let before = height()
            TurnView.bodies = 0
            click(window, at: NSPoint(x: 60, y: y))
            settle(0.5)
            growth = height() - before
            if TurnView.bodies > 0 || growth != 0 { print("Disclosure \(last): click at \(y) ran \(TurnView.bodies) turn bodies and changed the height by \(growth)") }
            return growth > 20
        }
        let y = try #require(header, "no click opened the last row")
        for (step, point) in [("collapse", y + growth), ("expand", y), ("collapse", y + growth)] {
            let before = height()
            distances.values = []
            click(window, at: NSPoint(x: 60, y: point))
            settle(1)
            let worst = distances.values.max() ?? 0
            print("Disclosure \(last): \(step) height \(before) -> \(height()), \(distances.values.count) geometry changes, farthest from the end \(worst)")
            #expect(abs(abs(height() - before) - growth) < 1, "\(step) missed the header: height \(before) -> \(height())")
            #expect(worst < 1, "\(step) left the end by \(worst) pt during the animation")
            #expect(distances.values.count < 10, "\(step) changed the scroll geometry \(distances.values.count) times")
        }
    }
}
