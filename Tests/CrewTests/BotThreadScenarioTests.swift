import Foundation
import Testing

private func recorded(_ profile: String) throws -> [HistoryRow] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/bot-thread/\(profile).history.json")
    return try decoder.decode([HistoryRow].self, from: Data(contentsOf: file))
}

private func rows(_ turns: [Turn]) -> [String] {
    turns.map { turn in
        if let message = turn.agentMessage { return "from \(message.handle)" }
        if let message = turn.outgoingMessage { return "to \(message.handle)" }
        if let prompt = turn.prompt { return "you: \(prompt.text)" }
        if turn.isRoutine { return "routine" }
        return "reply: \(turn.reply)"
    }
}

@Test func targetAnsweringWithMessageAgentShowsMessageToBetweenTheIncomingRows() throws {
    let history = try recorded("default")
    let shown = Transcript(history: history).visible.turns
    try #require(rows(shown) == [
        "you: Can you restart it? Sure.",
        "from scout",
        "to scout",
        "you: You shouldn't do Scout's work. You should just make sure Scout can do his work",
        "from scout",
        "to scout",
        "from scout",
    ])

    let call = try #require(history.first { $0.id == 1077 }?.toolCalls?.first)
    let outgoing = shown[5]
    #expect(outgoing.id == "\(call.id)-to")
    #expect(outgoing.status == .complete)
    #expect(outgoing.startedAt == Date(timeIntervalSince1970: try #require(history.first { $0.id == 1077 }?.timestamp)))
    #expect(outgoing.work.map(\.kind) == [.note("> I won't split it for you. You need bounded paging in the file tool; keep the task and tell the user that paging is the blocker.")])
    #expect(outgoing.deliveryFailure == nil)
}

@Test func refusedMessageAgentCallShowsItsRowWithTheFailure() throws {
    let shown = Transcript(history: try recorded("default")).visible.turns
    let refused = shown[2]
    #expect(refused.outgoingMessage?.body == "I saved the transcript to the shared folder.")
    #expect(refused.deliveryFailure?.target == "scout")
    #expect(refused.deliveryFailure?.isUnconfirmed == false)
    #expect(refused.deliveryFailure?.headline(for: "Scout") == "Message to Scout failed.")
}

@Test func senderShowsMessageToAfterUserStartedRoutineAndRelayTurns() throws {
    let shown = Transcript(history: try recorded("scout")).visible.turns
    #expect(rows(shown) == [
        "you: Or you try and learn how to transcribe?",
        "to default",
        "reply: Hermes found the original captions; the transcript is saved.",
        "routine",
        "to default",
        "reply: Understood. The summary stays my job. May Hermes add paging to the file tool?",
        "to default",
        "you: Which version do we run our instance on?",
        "to default",
        "reply: We're running Hermes Agent v0.23.0.",
    ])
}

@Test func messageToRowNeverSetsThePreview() throws {
    let window = try recorded("scout").filter { $0.id <= 241 }
    let transcript = Transcript(history: window).visible
    #expect(transcript.turns.last?.outgoingMessage?.handle == "default")
    #expect(transcript.lastMessage?.text == "I've asked Hermes to check the live version.")
}

@Test func coalescedDeliveryNoticeHidesTheNewMessageInTheEarlierExchange() throws {
    let shown = Transcript(history: try recorded("default")).visible.turns
    let earlier = shown[4]
    #expect(earlier.agentMessage?.body.hasPrefix("The morning summary failed") == true)
    #expect(earlier.work.contains { $0.kind == .note("Scout, read-only checks returned: Hermes Agent v0.23.0.") })
    #expect(!shown.contains { $0.agentMessage?.body == "Please check the live Hermes version of our instance." })
}
