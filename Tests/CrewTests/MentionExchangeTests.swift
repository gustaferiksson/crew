import Foundation
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/bot-mention")

private let sentAt = Date(timeIntervalSince1970: 1_792_136_000)

private func senderTranscript() throws -> Transcript {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return Transcript(history: try decoder.decode([HistoryRow].self, from: Data(contentsOf: scenario.appending(path: "crew-test.history.json"))))
}

private func mention(_ call: ToolCall, then later: [Turn] = []) -> Transcript {
    Transcript(turns: [
        Turn(id: "t1", prompt: Prompt(text: "@scout find flights", sentAt: sentAt), work: [WorkItem(id: "w1", kind: .tool(call), startedAt: sentAt)], status: .complete, startedAt: sentAt),
    ] + later)
}

private func call(status: ToolCall.Status = .success, result: String? = #"{"status": "queued", "process_id": "proc_ab12"}"#, target: String = "@scout") -> ToolCall {
    ToolCall(name: "message_agent", subject: "scout", arguments: #"{"target": "\#(target)", "message": "Find flights to Lofoten."}"#, result: result, status: status)
}

@Test func recordedMentionShowsTheSentMessageAndTheReply() throws {
    let transcript = try senderTranscript()
    let turn = try #require(transcript.turns.first { $0.prompt?.text == "@crew-test-peer hi" })
    let exchange = try #require(mentionExchange(with: "crew-test-peer", from: turn.id, in: transcript))
    #expect(exchange.message == "The user is greeting you; please respond with a brief hello.")
    guard case .replied(let reply, _) = exchange.outcome else { Issue.record("expected a reply, got \(exchange.outcome)"); return }
    #expect(reply == "Hello! Great to hear from you.")
}

@Test func plainMentionHasNoExchange() throws {
    let transcript = try senderTranscript()
    let turn = try #require(transcript.turns.first { $0.prompt?.text == "@crew-test-peer hi" })
    #expect(mentionExchange(with: "scout", from: turn.id, in: transcript) == nil)
}

@Test func queuedCallWithoutReplyIsAwaiting() {
    #expect(mentionExchange(with: "scout", from: "t1", in: mention(call()))?.outcome == .awaiting)
}

@Test func runningCallIsSending() {
    #expect(mentionExchange(with: "scout", from: "t1", in: mention(call(status: .running, result: nil)))?.outcome == .sending)
}

@Test func failedCallKeepsTheReason() {
    let failed = call(status: .error, result: #"{"error": "Unknown agent @scout"}"#)
    #expect(mentionExchange(with: "scout", from: "t1", in: mention(failed))?.outcome == .failed("Unknown agent @scout"))
}

@Test func queuedWithoutProcessIsRelayed() {
    let relayed = call(result: #"{"status": "queued", "to": "@scout@studio"}"#, target: "@scout@studio")
    #expect(mentionExchange(with: "scout", from: "t1", in: mention(relayed))?.outcome == .relayed)
}

@Test func deliveryWithoutReplyIsDelivered() {
    let delivery = Turn(id: "t2", delivery: "proc_ab12", status: .complete, startedAt: sentAt.addingTimeInterval(30))
    #expect(mentionExchange(with: "scout", from: "t1", in: mention(call(), then: [delivery]))?.outcome == .delivered)
}

@Test func eachMentionGetsItsOwnReplyInOrder() {
    let second = Turn(id: "t2", prompt: Prompt(text: "@scout and trains?", sentAt: sentAt), work: [WorkItem(id: "w2", kind: .tool(call(result: #"{"status": "queued", "process_id": "proc_cd34"}"#)), startedAt: sentAt)], status: .complete, startedAt: sentAt.addingTimeInterval(10))
    let reply = { (id: String, text: String, offset: TimeInterval) in
        Turn(id: id, agentMessage: AgentMessage("Message from 🤖 Scout (@scout): \(text)"), status: .complete, startedAt: sentAt.addingTimeInterval(offset))
    }
    let transcript = mention(call(), then: [second, reply("t3", "Flights found.", 20), reply("t4", "Trains found.", 30)])
    #expect(mentionExchange(with: "scout", from: "t1", in: transcript)?.outcome == .replied("Flights found.", at: sentAt.addingTimeInterval(20)))
    #expect(mentionExchange(with: "scout", from: "t2", in: transcript)?.outcome == .replied("Trains found.", at: sentAt.addingTimeInterval(30)))
}

@Test func newerMentionWithoutReplyStaysWaiting() {
    let second = Turn(id: "t2", prompt: Prompt(text: "@scout and trains?", sentAt: sentAt), work: [WorkItem(id: "w2", kind: .tool(call(result: #"{"status": "queued", "process_id": "proc_cd34"}"#)), startedAt: sentAt)], status: .complete, startedAt: sentAt.addingTimeInterval(10))
    let reply = Turn(id: "t3", agentMessage: AgentMessage("Message from 🤖 Scout (@scout): Flights found."), status: .complete, startedAt: sentAt.addingTimeInterval(20))
    #expect(mentionExchange(with: "scout", from: "t2", in: mention(call(), then: [second, reply]))?.outcome == .awaiting)
}

@Test func hermesTargetMatchesTheDefaultBot() {
    let reply = Turn(id: "t2", agentMessage: AgentMessage("Message from 🤖 Hermes (@hermes): Booked."), status: .complete, startedAt: sentAt.addingTimeInterval(20))
    let exchange = mentionExchange(with: "default", from: "t1", in: mention(call(target: "@hermes"), then: [reply]))
    #expect(exchange?.outcome == .replied("Booked.", at: sentAt.addingTimeInterval(20)))
}
