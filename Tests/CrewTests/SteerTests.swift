import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())
private let steerText = "Also include the word STEERED in your final reply."

private struct HistoryPage: Decodable {
    let messages: [HistoryRow]
}

private func steerHistory() throws -> Transcript {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let page = try decoder.decode(HistoryPage.self, from: Data(contentsOf: fixtures.appending(path: "chat.history.v0.21.7.json")))
    return Transcript(history: page.messages.filter { (62...66).contains($0.id) })
}

private func steerEvents() throws -> [GatewayEvent] {
    let lines = try String(contentsOf: fixtures.appending(path: "chat.steer-turn.v0.21.7.jsonl"), encoding: .utf8).split(separator: "\n")
    return try lines.map { try JSONDecoder().decode(GatewayEvent.self, from: Data($0.utf8)) }
}

private func shape(_ transcript: Transcript) -> [String] {
    transcript.turns.map { turn in
        let work = turn.work.compactMap { item -> String? in
            if case .tool(let call) = item.kind { return "tool \(call.name)" }
            if case .note(let text) = item.kind { return "note \(text)" }
            return nil
        }
        return "\(turn.isSteer ? "steer" : "prompt") \(turn.prompt?.text ?? "-") | \(work.joined(separator: ", ")) | answer \(turn.answer ?? "-") | reply \(turn.reply)"
    }
}

@MainActor @Test func aLiveSteerLandsWhereHistoryPutsIt() throws {
    var start = Transcript()
    start.begin(prompt: "Use the terminal to run: sleep 6 && echo step-one. Then reply with the output.", id: "62")
    start.wait(Prompt(text: steerText, sentAt: .now), as: .steer)
    let session = ChatSession(fixture: crewTest, transcript: start, todos: [])
    #expect(session.transcript.visible.turns.last?.pending == .steer)

    for event in try steerEvents() { session.apply(event) }

    #expect(session.transcript.waiting.isEmpty)
    #expect(shape(session.transcript.visible) == shape(try steerHistory().visible))
    #expect(shape(session.transcript) == [
        "prompt Use the terminal to run: sleep 6 && echo step-one. Then reply with the output. | tool terminal | answer - | reply ",
        "steer \(steerText) |  | answer - | reply step-one\nSTEERED",
    ])
}

@Test func theFirstTextAfterASteerIsItsAnswer() {
    var transcript = Transcript()
    transcript.begin(prompt: "Tidy the profile settings")
    transcript.apply(.toolStart(id: "a", name: "terminal", context: nil, arguments: "{}"))
    transcript.wait(Prompt(text: "Only you handle Hermes settings", sentAt: .now), as: .steer)
    transcript.apply(.toolComplete(id: "a", duration: 1, summary: nil, result: "{}"))
    transcript.apply(.messageDelta("Agreed. I alone handle Hermes settings."))
    transcript.apply(.toolStart(id: "b", name: "read_file", context: nil, arguments: "{}"))
    transcript.apply(.toolComplete(id: "b", duration: 1, summary: nil, result: "{}"))
    transcript.apply(.messageDelta("Checking the plugins next."))
    transcript.apply(.toolStart(id: "c", name: "terminal", context: nil, arguments: "{}"))
    transcript.apply(.toolComplete(id: "c", duration: 1, summary: nil, result: "{}"))
    transcript.apply(.messageComplete(text: "Done.", status: .complete, error: nil))

    #expect(transcript.turns.count == 2)
    #expect(transcript.turns[0].status == .complete)
    #expect(transcript.turns[1].prompt?.text == "Only you handle Hermes settings")
    #expect(transcript.turns[1].answer == "Agreed. I alone handle Hermes settings.")
    #expect(shape(transcript)[1] == "steer Only you handle Hermes settings | tool read_file, note Checking the plugins next., tool terminal | answer Agreed. I alone handle Hermes settings. | reply Done.")
}

@Test func historySplitsTheTurnAndShowsTheAnswerTheSameWay() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([HistoryRow].self, from: Data(#"""
    [
     {"id": 1, "role": "user", "content": "Tidy the profile settings", "timestamp": 100},
     {"id": 2, "role": "assistant", "content": "", "timestamp": 101, "tool_calls": [{"id": "a", "function": {"name": "terminal", "arguments": "{}"}}]},
     {"id": 3, "role": "tool", "content": "{}", "timestamp": 102, "tool_call_id": "a"},
     {"id": 4, "role": "user", "content": "[OUT-OF-BAND USER MESSAGE]\nOnly you handle Hermes settings\n[/OUT-OF-BAND USER MESSAGE]", "display_kind": "steer", "display_content": "Only you handle Hermes settings", "timestamp": 103},
     {"id": 5, "role": "assistant", "content": "Agreed. I alone handle Hermes settings.", "timestamp": 104, "tool_calls": [{"id": "b", "function": {"name": "read_file", "arguments": "{}"}}]},
     {"id": 6, "role": "tool", "content": "{}", "timestamp": 105, "tool_call_id": "b"},
     {"id": 7, "role": "assistant", "content": "Done.", "timestamp": 106}
    ]
    """#.utf8))
    let transcript = Transcript(history: rows)
    #expect(shape(transcript) == [
        "prompt Tidy the profile settings | tool terminal | answer - | reply ",
        "steer Only you handle Hermes settings | tool read_file | answer Agreed. I alone handle Hermes settings. | reply Done.",
    ])
}

@Test func aSteerNotTakenBeforeTheTurnEndsBecomesTheNextTurn() {
    var transcript = Transcript()
    transcript.begin(prompt: "Summarise the inbox")
    transcript.wait(Prompt(text: "Skip newsletters", sentAt: .now), as: .steer)
    transcript.wait(Prompt(text: "Then archive them", sentAt: .now), as: .queued)
    transcript.apply(.messageComplete(text: "Two invoices.", status: .complete, error: nil))

    #expect(transcript.visible.turns.map(\.pending) == [nil, .steer, .queued])
    #expect(transcript.dequeue() == nil)

    transcript.begin(remote: "Skip newsletters", displayKind: nil, at: .now)
    #expect(transcript.waiting.map(\.pending) == [.queued])
    transcript.apply(.messageComplete(text: "Skipped.", status: .complete, error: nil))
    #expect(transcript.dequeue()?.text == "Then archive them")
    #expect(transcript.turns.map(\.prompt?.text) == ["Summarise the inbox", "Skip newsletters"])
}

@Test func steersSortBeforeQueuedMessagesAndDropInSendOrder() {
    var transcript = Transcript()
    transcript.wait(Prompt(text: "first queued", sentAt: .now), as: .queued)
    transcript.wait(Prompt(text: "a steer", sentAt: .now), as: .steer)
    transcript.wait(Prompt(text: "second queued", sentAt: .now), as: .queued)
    #expect(transcript.waiting.map(\.prompt?.text) == ["a steer", "first queued", "second queued"])
    #expect(transcript.dropWaiting() == ["a steer", "first queued", "second queued"])
    #expect(transcript.waiting.isEmpty)
}

@Test func aSteerWaitsForTheWholeToolBatchAndTheNextModelCall() {
    var transcript = Transcript()
    transcript.begin(prompt: "Tidy up")
    transcript.wait(Prompt(text: "Skip the logs", sentAt: .now), as: .steer)
    transcript.apply(.toolStart(id: "a", name: "terminal", context: nil, arguments: "{}"))
    transcript.apply(.toolStart(id: "b", name: "read_file", context: nil, arguments: "{}"))
    transcript.apply(.toolComplete(id: "a", duration: 1, summary: nil, result: "{}"))
    #expect(transcript.waiting.map(\.pending) == [.steer])
    transcript.apply(.toolComplete(id: "b", duration: 1, summary: nil, result: "{}"))
    #expect(transcript.waiting.map(\.pending) == [.taken])
    transcript.apply(.toolStart(id: "c", name: "terminal", context: nil, arguments: "{}"))
    #expect(transcript.turns.count == 1)
    transcript.takeSteers()
    #expect(transcript.turns.map(\.prompt?.text) == ["Tidy up", "Skip the logs"])
    #expect(transcript.turns[0].work.count == 3)
}

@Test func waitingMessagesNeverBecomeThePreview() {
    var transcript = Transcript()
    transcript.begin(prompt: "Summarise the inbox")
    transcript.apply(.messageComplete(text: "Two invoices.", status: .complete, error: nil))
    transcript.wait(Prompt(text: "Then archive them", sentAt: .now), as: .queued)
    #expect(transcript.preview == "Two invoices.")
}

@Test func stoppingKeepsASteerTheAgentAlreadyTook() {
    var transcript = Transcript()
    transcript.begin(prompt: "Tidy up")
    transcript.wait(Prompt(text: "Skip the logs", sentAt: .now), as: .steer)
    transcript.apply(.toolStart(id: "a", name: "terminal", context: nil, arguments: "{}"))
    transcript.apply(.toolComplete(id: "a", duration: 1, summary: nil, result: "{}"))
    transcript.wait(Prompt(text: "Then the cache", sentAt: .now), as: .queued)
    #expect(transcript.dropWaiting { $0.pending != .taken } == ["Then the cache"])
    transcript.apply(.messageComplete(text: "", status: .interrupted, error: nil))
    #expect(transcript.turns.map(\.prompt?.text) == ["Tidy up", "Skip the logs"])
    #expect(transcript.waiting.isEmpty)
}

@MainActor @Test func aRecordedSteerAnswerReadsTheSameLiveAndAfterAReload() throws {
    let lines = try String(contentsOf: fixtures.appending(path: "chat.steer-answer-turn.jsonl"), encoding: .utf8).split(separator: "\n")
    let events = try lines.map { try JSONDecoder().decode(GatewayEvent.self, from: Data($0.utf8)) }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let history = Transcript(history: try decoder.decode([HistoryRow].self, from: Data(contentsOf: fixtures.appending(path: "chat.steer-answer.history.json"))))

    var start = Transcript()
    start.begin(prompt: "Use the terminal to run: sleep 8 && echo step-one. Then run: echo step-two. Then reply with both outputs.", id: "8")
    start.wait(Prompt(text: "Before your next tool call, reply to this note in one short sentence, then carry on.", sentAt: .now), as: .steer)
    let session = ChatSession(fixture: crewTest, transcript: start, todos: [])
    for event in events { session.apply(event) }

    #expect(shape(session.transcript) == shape(history))
    #expect(shape(history) == [
        "prompt Use the terminal to run: sleep 8 && echo step-one. Then run: echo step-two. Then reply with both outputs. | tool terminal | answer - | reply ",
        "steer Before your next tool call, reply to this note in one short sentence, then carry on. | tool terminal | answer I’ve received your note and will continue with the second command. | reply ```text\nstep-one\nstep-two\n```",
    ])
    #expect(!session.transcript.turns[1].work.contains { if case .thinking = $0.kind { true } else { false } })
}
