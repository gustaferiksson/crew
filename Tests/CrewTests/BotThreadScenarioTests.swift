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
        "you: Let Scout do that himself; just make sure he can.",
        "from scout",
        "to scout",
        "from scout",
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
        "you: Can you get the transcript yourself?",
        "to default",
        "reply: Hermes found the original captions; the transcript is saved.",
        "routine",
        "to default",
        "reply: Understood. The summary stays my job. May Hermes add paging to the file tool?",
        "to default",
        "you: Which Hermes version are we on?",
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

@Test func coalescedDeliveryNoticeSplitsTheAppendedMessageIntoItsOwnExchange() throws {
    let history = try recorded("default")
    let time = { (id: Int) in Date(timeIntervalSince1970: history.first { $0.id == id }?.timestamp ?? 0) }
    let shown = Transcript(history: history).visible.turns
    try #require(shown.count == 8)
    #expect(Set(shown.map(\.id)).count == shown.count)

    let earlier = shown[4]
    #expect(earlier.agentMessage?.body.hasPrefix("The morning summary failed") == true)
    #expect(earlier.finishedAt == time(1082))
    #expect(!earlier.work.contains { $0.kind == .note("Scout, read-only checks returned: Hermes Agent v0.23.0.") })

    #expect(shown[6].agentMessage?.body == "Understood, I keep the task. The file tool only has head and tail reads; proposed fix: a paged reader.")
    #expect(shown[6].work.last?.kind == .note("Scout confirmed the gap: the file tool has no paging. **Do you approve adding a paged reader?**"))

    let appended = shown[7]
    #expect(appended.agentMessage == AgentMessage(sender: "Scout", handle: "scout", body: "Please check the live Hermes version of our instance."))
    #expect(appended.id == "1082-1")
    #expect(appended.delivery == nil)
    #expect(appended.status == .complete)
    #expect(appended.startedAt == time(1083))
    #expect(appended.finishedAt == time(1091))
    try #require(appended.work.count == 3)
    #expect(appended.work[0].kind == .note("> Please check the live Hermes version of our instance."))
    guard case .tool(let check) = appended.work[1].kind else { Issue.record("expected the version check"); return }
    #expect(check.name == "terminal")
    #expect(check.result == #"{"output": "Hermes Agent v0.23.0", "exit_code": 0, "error": null}"#)
    #expect(appended.work[2].kind == .note("Scout, read-only checks returned: Hermes Agent v0.23.0."))
}

@Test func coalescedExchangeSetsThePreview() throws {
    let history = try recorded("default")
    let latest = LastMessage(text: "Message from Scout", date: Date(timeIntervalSince1970: try #require(history.first { $0.id == 1091 }?.timestamp)))
    #expect(Transcript(history: history).visible.lastMessage == latest)

    let window = Transcript(history: history.filter { $0.id >= 1082 }).visible
    #expect(rows(window.turns) == ["from scout"])
    #expect(window.lastMessage == latest)
}

@Test func coalescedNoticeSplitsAtEachNoticeAndKeepsAnAppendedPrompt() throws {
    let recordedNotice = try #require(try recorded("default").first { $0.id == 1082 }?.content)
    let notice = String(try #require(recordedNotice.firstRange(of: "\n\nMessage from 🤖").map { recordedNotice[..<$0.lowerBound] }))
    let merged = notice + "\n\n" + notice.replacingOccurrences(of: "proc_01789a0d57b0", with: "proc_02") + "\n\nWhich version are we on?"
    let stored: [[String: Any]] = [
        ["id": 1, "role": "user", "content": merged, "timestamp": 100.0],
        ["id": 2, "role": "assistant", "content": "Hermes Agent v0.23.0.", "timestamp": 160.0],
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let turns = Transcript(history: try decoder.decode([HistoryRow].self, from: JSONSerialization.data(withJSONObject: stored))).turns
    try #require(turns.count == 3)
    #expect(turns.map(\.delivery) == ["proc_01789a0d57b0", "proc_02", nil])
    #expect(turns[0].deliveryFailure == nil)
    #expect(turns[2].prompt?.text == "Which version are we on?")
    #expect(turns[2].reply == "Hermes Agent v0.23.0.")
    #expect(turns[2].startedAt == Date(timeIntervalSince1970: 160))
    #expect(Set(turns.map(\.id)).count == 3)
}
