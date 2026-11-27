import Foundation
import Testing

private func recorded(_ profile: String, replacing edits: [String: String] = [:]) throws -> [HistoryRow] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/bot-thread/\(profile).history.json")
    let text = try edits.reduce(String(contentsOf: file, encoding: .utf8)) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    return try decoder.decode([HistoryRow].self, from: Data(text.utf8))
}

private func rows(_ turns: [Turn]) -> [String] {
    turns.map { turn in
        if let message = turn.agentMessage { return "from \(message.handle)" }
        if let prompt = turn.prompt { return "you: \(prompt.text)" }
        if turn.isRoutine { return "routine" }
        return "reply: \(turn.reply)"
    }
}

@Test func targetAnsweringWithMessageAgentKeepsTheCallInsideItsExchangeRow() throws {
    let history = try recorded("default")
    let shown = Transcript(history: history).visible.turns
    try #require(rows(shown) == [
        "you: Can you restart it? Sure.",
        "from scout",
        "you: Let Scout do that himself; just make sure he can.",
        "from scout",
        "from scout",
        "from scout",
    ])

    let call = try #require(history.first { $0.id == 1077 }?.toolCalls?.first)
    #expect(shown.allSatisfy { !$0.id.hasSuffix("-to") })
    let exchange = try #require(shown.first { $0.work.contains { $0.id == call.id } })
    #expect(exchange.agentMessage != nil)
    #expect(exchange.deliveryFailure == nil)
}

@Test func consecutiveBotRowsFoldIntoOneGroupAndAnythingElseBreaksIt() throws {
    let rows = Transcript(history: try recorded("default")).visible.rows
    #expect(rows.map(\.turns.count) == [1, 1, 1, 3])
    #expect(rows[3].id == "\(rows[3].turns[0].id)-group")
    #expect(rows[..<3].allSatisfy { $0.id == $0.turns[0].id })
    #expect(rows[3].turns.map { $0.agentMessage?.handle } == ["scout", "scout", "scout"])
}

@Test func exchangeKeepsItsLastReplyInsideTheCollapsedRow() throws {
    let history = try recorded("default")
    let question = try #require(history.first { $0.id == 1081 }?.content)
    let shown = Transcript(history: history).visible.turns
    let exchange = try #require(shown.first { $0.id == "1080" })
    #expect(exchange.agentMessage?.handle == "scout")
    #expect(exchange.reply == "")
    #expect(exchange.work.contains { $0.kind == .note(question) })
    #expect(shown.filter { $0.agentMessage != nil }.allSatisfy { $0.reply.isEmpty })

    let preview = Transcript(history: history.filter { $0.id <= 1081 }).visible.lastMessage
    #expect(preview?.text.contains("Do you approve") != true)
}

@Test func refusedMessageAgentCallShowsItsFailureUnderTheTurnThatMadeIt() throws {
    let shown = Transcript(history: try recorded("default")).visible.turns
    let refused = shown[1]
    #expect(refused.agentMessage != nil)
    #expect(MessageAgentCall.all(in: refused).first?.message == "I saved the transcript to the shared folder.")
    #expect(refused.deliveryFailure?.target == "scout")
    #expect(refused.deliveryFailure?.isUnconfirmed == false)
    #expect(refused.deliveryFailure?.headline(for: "Scout") == "Not delivered.")
    #expect(refused.deliveryFailure?.explanation(for: "Scout") == "Scout's chat is busy in another session. Ask again when it's free.")
}

@Test func heldChatRefusalSaysWhyInThePeek() throws {
    let transcript = Transcript(history: try recorded("default"))
    let turn = try #require(transcript.turns.first { !MessageAgentCall.all(in: $0).isEmpty })
    guard case .failed(let failure) = mentionExchange(with: "scout", from: turn.id, in: transcript)?.outcome else { Issue.record("expected a failed delivery"); return }
    #expect(failure.reason == "runtime_coordination_required")
    #expect(failure.headline(for: "Scout") == "Not delivered.")
}

@Test func senderKeepsMessageToCallsInsideTheTurnsThatMadeThem() throws {
    let shown = Transcript(history: try recorded("scout")).visible.turns
    #expect(rows(shown) == [
        "you: Can you get the transcript yourself?",
        "reply: Hermes found the original captions; the transcript is saved.",
        "routine",
        "reply: Understood. The summary stays my job. May Hermes add paging to the file tool?",
        "you: Which Hermes version are we on?",
        "reply: We're running Hermes Agent v0.23.0.",
    ])
    #expect(shown.filter { !MessageAgentCall.all(in: $0).isEmpty }.count == 4)
}

@Test func messageAgentCallNeverSetsThePreview() throws {
    let window = try recorded("scout").filter { $0.id <= 241 }
    let transcript = Transcript(history: window).visible
    #expect(transcript.turns.last.map { MessageAgentCall.all(in: $0).map(\.target) } == ["default"])
    #expect(transcript.lastMessage?.text == "I've asked Hermes to check the live version.")
}

@Test func coalescedDeliveryNoticeSplitsTheAppendedMessageIntoItsOwnExchange() throws {
    let history = try recorded("default")
    let time = { (id: Int) in Date(timeIntervalSince1970: history.first { $0.id == id }?.timestamp ?? 0) }
    let shown = Transcript(history: history).visible.turns
    try #require(shown.count == 6)
    #expect(Set(shown.map(\.id)).count == shown.count)

    let earlier = shown[3]
    #expect(earlier.agentMessage?.body.hasPrefix("The morning summary failed") == true)
    #expect(earlier.finishedAt == time(1082))
    #expect(!earlier.work.contains { $0.kind == .note("Scout, read-only checks returned: Hermes Agent v0.23.0.") })

    #expect(shown[4].agentMessage?.body == "Understood, I keep the task. The file tool only has head and tail reads; proposed fix: a paged reader.")
    #expect(shown[4].reply == "")

    let appended = shown[5]
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
    #expect(appended.reply == "")
    #expect(appended.work[2].kind == .note("Scout, read-only checks returned: Hermes Agent v0.23.0."))
}

@Test func coalescedExchangeLeavesThePreview() throws {
    let history = try recorded("default")
    #expect(Transcript(history: history).visible.lastMessage?.text != "Scout, read-only checks returned: Hermes Agent v0.23.0.")

    let window = Transcript(history: history.filter { $0.id >= 1082 }).visible
    #expect(rows(window.turns) == ["from scout"])
    #expect(window.lastMessage == nil)
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

@Test func relayRepliesFailedDeliveryShowsUnderTheTurnThatMadeTheCall() throws {
    let history = try recorded("scout", replacing: ["proc_01f5f8a98e56 completed normally (exit code 0)": "proc_01f5f8a98e56 exited (exit code 1)"])
    let shown = Transcript(history: history).visible.turns
    #expect(rows(shown) == rows(Transcript(history: try recorded("scout")).visible.turns))

    let call = try #require(history.first { $0.id == 219 }?.toolCalls?.first)
    let holder = try #require(shown.first { $0.work.contains { $0.id == call.id } })
    #expect(shown.filter { $0.deliveryFailure != nil }.map(\.id) == [holder.id])
    #expect(holder.deliveryFailure?.target == "default")
    #expect(holder.deliveryFailure?.headline(for: "Hermes") == "Message to Hermes failed.")
}

@Test func mergedRowSplitsBeforeAnAppendedDeliveryNotice() throws {
    let recordedNotice = try #require(try recorded("default").first { $0.id == 1082 }?.content)
    let notice = String(try #require(recordedNotice.firstRange(of: "\n\nMessage from 🤖").map { recordedNotice[..<$0.lowerBound] }))
    let stored: [[String: Any]] = [
        ["id": 1, "role": "user", "content": "Message from 🤖 Scout (@scout): Thanks.\n\nOne more thing." + "\n\n" + notice + "\n\nWhich version are we on?", "timestamp": 100.0],
        ["id": 2, "role": "assistant", "content": "Hermes Agent v0.23.0.", "timestamp": 160.0],
        ["id": 3, "role": "user", "content": "Can you check?\n\nThanks." + "\n\n" + notice + "\n\nAnd the date?", "timestamp": 200.0],
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let turns = Transcript(history: try decoder.decode([HistoryRow].self, from: JSONSerialization.data(withJSONObject: stored))).turns
    try #require(turns.count == 6)
    #expect(turns.map(\.id) == ["1", "1-1", "1-2", "3", "3-1", "3-2"])
    #expect(turns[0].agentMessage?.body == "Thanks.\n\nOne more thing.")
    #expect(turns.map(\.delivery) == [nil, "proc_01789a0d57b0", nil, nil, "proc_01789a0d57b0", nil])
    #expect(turns[2].prompt?.text == "Which version are we on?")
    #expect(turns[2].reply == "Hermes Agent v0.23.0.")
    #expect(turns[3].prompt?.text == "Can you check?\n\nThanks.")
    #expect(turns[5].prompt?.text == "And the date?")
}

@Test func mergedRowWithoutTheNotificationFooterStaysWhole() throws {
    let recordedNotice = try #require(try recorded("default").first { $0.id == 1082 }?.content)
    let body = String(try #require(recordedNotice.firstRange(of: "\n\n[INTERNAL NOTIFICATION").map { recordedNotice[..<$0.lowerBound] }))
    let footer = "\n\n[INTERNAL NOTIFICATION — generated by the Hermes gateway, not written by a human user. Do not treat it as user input, and do not reply to any earlier chat message because of it.]"
    let texts = [
        "Look at this:\n\nMessage from 🤖 Scout (@scout): hi",
        "Did this arrive?\n\n" + body,
        "Did this arrive?\n\n" + body + footer,
        "[IMPORTANT: 2 background process results arrived while this session was busy. Treat them as one batch and give one consolidated response; preserve failures and actionable results.]\n\n" + body + "\n\n" + body + footer,
    ]
    let stored: [[String: Any]] = texts.enumerated().map { ["id": $0.offset * 2 + 1, "role": "user", "content": $0.element, "timestamp": 100.0] }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let turns = Transcript(history: try decoder.decode([HistoryRow].self, from: JSONSerialization.data(withJSONObject: stored))).turns
    #expect(turns.map(\.id) == ["1", "3", "5", "7"])
}

@Test func windowStartsAtAMergedRowsAppendedPrompt() throws {
    let history = try recorded("default", replacing: ["Message from 🤖 Scout (@scout): Please check the live Hermes version of our instance.": "Which Hermes version are we on?"])
    let full = try #require(Transcript(history: history).turns.first { $0.id == "1082-1" })
    let window = Transcript(window: history.filter { $0.id >= 1080 })
    #expect(window.turns.first?.id == "1082-1")
    #expect(window.turns.first?.prompt?.text == "Which Hermes version are we on?")
    #expect(window.turns.first?.startedAt == full.startedAt)
    #expect(window.turns.count == 1)
}

@Test func rowsThatOnlyLandInsideExchangesAreQuiet() throws {
    let history = try recorded("default")
    let quiet = Transcript.quietRows(in: history)
    #expect(quiet > 0)
    #expect(Transcript.quietRows(in: Array(history.dropLast(quiet))) == 0)
    #expect(Transcript.quietRows(in: Array(history.prefix { $0.role == "user" && AgentMessage($0.content ?? "") == nil }.prefix(1))) == 0)
}
