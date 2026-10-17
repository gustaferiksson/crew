import Foundation
import Testing

private let sentAt = Date(timeIntervalSince1970: 1_792_136_000)

private let roster = (0..<10).map { index in
    Bot(name: "bot\(index)", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta(title: "Bot Number \(index)"))
}

private let longChat = Transcript(turns: (0..<300).flatMap { index in
    let start = sentAt.addingTimeInterval(Double(index) * 60)
    let call = ToolCall(name: "message_agent", subject: "bot1", arguments: #"{"target": "bot1", "message": "Find flights to Lofoten."}"#, result: #"{"status": "queued", "process_id": "proc_\#(index)"}"#, status: .success)
    return [
        Turn(id: "p\(index)", prompt: Prompt(text: "Can you ask @bot1 to find flights, and @bot-number-2, please add it to my calendar?", sentAt: start), work: [WorkItem(id: "p\(index)-w0", kind: .tool(call), startedAt: start)], status: .complete, startedAt: start),
        Turn(id: "r\(index)", agentMessage: AgentMessage("Message from 🤖 Bot Number 1 (@bot1): Found three options."), status: .complete, startedAt: start.addingTimeInterval(30)),
    ]
})

@Test func resolvingTagsForEveryBubbleInALongChatIsCheap() {
    let prompts = longChat.turns.compactMap(\.prompt?.text)
    let elapsed = ContinuousClock().measure {
        for text in prompts { #expect(mentionSegments(in: text, among: roster).count == 5) }
    }
    print("mentionSegments: \(prompts.count) bubbles x \(roster.count) bots in \(elapsed)")
    #expect(elapsed < .milliseconds(250))
}

@Test func peekingTheNewestMentionInALongChatIsCheap() {
    let start = ContinuousClock.now
    let exchange = mentionExchange(with: "bot1", from: "p299", in: longChat)
    let elapsed = ContinuousClock.now - start
    guard case .replied = exchange?.outcome else {
        Issue.record("expected the paired reply, got \(String(describing: exchange))")
        return
    }
    print("mentionExchange: newest of \(longChat.turns.count) turns in \(elapsed)")
    #expect(elapsed < .milliseconds(50))
}
