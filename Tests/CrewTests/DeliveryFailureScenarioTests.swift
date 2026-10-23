import Foundation
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/delivery-failure")

private let providerError = #"HTTP 400: {"detail":"The 'gpt-crew-test-missing' model is not supported when using Codex with a ChatGPT account."}"#

private func recorded<Value: Decodable>(_ name: String, as type: Value.Type, reason: String = "unknown", keys: JSONDecoder.KeyDecodingStrategy = .convertFromSnakeCase) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = keys
    let text = try String(contentsOf: scenario.appending(path: "\(name).json"), encoding: .utf8)
    return try decoder.decode(type, from: Data(text.replacingOccurrences(of: #"\"reason\": \"unknown\""#, with: #"\"reason\": \"\#(reason)\""#).utf8))
}

private func sender(reason: String = "unknown") throws -> Transcript {
    Transcript(history: try recorded("crew-test.history", as: [HistoryRow].self, reason: reason))
}

private func peekOutcome(_ transcript: Transcript) throws -> MentionExchange.Outcome? {
    let turn = try #require(transcript.turns.first { $0.prompt?.text == "@crew-test-peer hi" })
    return mentionExchange(with: "crew-test-peer", from: turn.id, in: transcript)?.outcome
}

@Test func recordedFailedDeliveryIsNotDeliveredInThePeek() throws {
    #expect(try peekOutcome(try sender()) == .failed(DeliveryFailure(reason: "unknown", detail: providerError, target: "crew-test-peer")))
}

@Test func recordedFailedDeliveryShowsAFootnoteUnderTheFollowUp() throws {
    let followUp = try #require(try sender().visible.turns.last)
    #expect(followUp.reply == "Crew Peer couldn’t reply because its configured model, `gpt-crew-test-missing`, is unsupported by the connected ChatGPT account.")
    #expect(followUp.deliveryFailure == DeliveryFailure(reason: "unknown", detail: providerError, target: "crew-test-peer"))
    #expect(followUp.deliveryFailure?.headline(for: "Crew Peer") == "Message to Crew Peer failed.")
    #expect(followUp.deliveryFailure?.explanation(for: "Crew Peer") == nil)
}

@Test func typedReasonSaysWhyAndWhetherToRetry() throws {
    let busy = try sender(reason: "target_busy")
    #expect(busy.visible.turns.last?.deliveryFailure?.headline(for: "Crew Peer") == "Not delivered.")
    guard case .failed(let failure) = try peekOutcome(busy) else { Issue.record("expected a failed delivery"); return }
    #expect(failure.explanation(for: "Crew Peer") == "Crew Peer is busy right now. Ask again later.")
    let login = try #require(try sender(reason: "provider_auth_or_access").visible.turns.last?.deliveryFailure)
    #expect(login.headline(for: "Crew Peer") == "Crew Peer couldn't answer.")
    #expect(login.explanation(for: "Crew Peer") == "Crew Peer's AI provider rejected its login or access. Asking again won't help.")
}

@Test func everyHermesReasonHasASentence() {
    let codes = ["target_busy", "runtime_offline", "delivery_timeout", "queued_expired", "cancelled", "provider_rate_limit", "provider_server_error", "provider_auth_or_access", "provider_quota_limit", "context_overflow", "missing_config", "model_unavailable", "agent_blocked", "target_scope_unresolved"]
    for code in codes {
        #expect(DeliveryFailure(reason: code).explanation(for: "Emil")?.contains("Emil") == true, "\(code)")
    }
    #expect(DeliveryFailure(reason: "unknown").explanation(for: "Emil") == nil)
    #expect(DeliveryFailure(reason: "something_new").explanation(for: "Emil") == nil)
}

@Test func relayWaiterReasonIsRead() {
    let notice = "[IMPORTANT: Background process proc_51ab exited (exit code 1).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery --wait-reply /tmp/reply.json '@scout on mini' 600\nOutput:\nDelivery to @scout on mini failed [reason: runtime_offline]: Desktop is not connected\n]"
    #expect(DeliveryFailure(notice: notice) == DeliveryFailure(reason: "runtime_offline", detail: "Desktop is not connected"))
}

@Test func failureWithoutAShapeHasNoReason() {
    let notice = "[IMPORTANT: Background process proc_51ab exited (exit code 1).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery query-file /tmp/dm\nOutput:\nSomething went wrong.\n]"
    #expect(DeliveryFailure(notice: notice) == DeliveryFailure())
    #expect(DeliveryFailure(notice: notice.replacingOccurrences(of: "exited (exit code 1)", with: "completed normally (exit code 0)")) == nil)
}

@Test func immediateRefusalCarriesItsReasonToTheToolRow() {
    let refused = ToolCall(name: "message_agent", subject: "Hi", arguments: #"{"target": "@Scout", "message": "Hi"}"#, result: #"{"error": "Desktop is offline.", "reason": "runtime_offline"}"#, status: .error)
    #expect(refused.deliveryFailure == DeliveryFailure(reason: "runtime_offline", detail: "Desktop is offline.", target: "scout"))
    let start = Date(timeIntervalSince1970: 1_792_136_000)
    let transcript = Transcript(turns: [Turn(id: "t1", prompt: Prompt(text: "@scout hi", sentAt: start), work: [WorkItem(id: "w1", kind: .tool(refused), startedAt: start)], status: .complete, startedAt: start)])
    #expect(mentionExchange(with: "scout", from: "t1", in: transcript)?.outcome == .failed(DeliveryFailure(reason: "runtime_offline", detail: "Desktop is offline.", target: "scout")))
    #expect(ToolCall(name: "message_agent", subject: "", arguments: "{}", result: #"{"status": "queued", "process_id": "proc_1"}"#, status: .success).deliveryFailure == nil)
}

@Test func botRowsKeepTheBotsOwnWords() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.after", as: Roster.self, keys: .useDefaultKeys).profiles)
    store.apply(live: try recorded("active_list.after", as: ActiveList.self, keys: .useDefaultKeys).sessions)
    store.showPreview(of: "crew-test", from: try recorded("crew-test.preview", as: [HistoryRow].self))
    #expect(store.previews["crew-test"]?.text == "Crew Peer couldn’t reply because its configured model, `gpt-crew-test-missing`, is unsupported by the connected ChatGPT account.")
    #expect(try sender().preview == store.previews["crew-test"])
    let chats = ChatSessions(fixture: ["crew-test": ChatSession(fixture: try #require(store.bots.first { $0.name == "crew-test" }), transcript: try sender(), todos: [])])
    #expect(chats.status(of: "crew-test", in: store) != .failed)
}

@Test func targetChatShowsTheExchangeWithItsFailedTurn() throws {
    let transcript = Transcript(history: try recorded("crew-test-peer.history", as: [HistoryRow].self))
    let shown = transcript.visible.turns
    #expect(shown.count == 1)
    #expect(shown.first?.agentMessage?.sender == "Crew Test")
    #expect(shown.first?.deliveryFailure == nil)
}

@Test func targetExchangeRowCarriesItsOwnFailedReplyBack() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let text = try String(contentsOf: scenario.deletingLastPathComponent().appending(path: "bot-mention/crew-test-peer.history.json"), encoding: .utf8)
    let failed = Data(text.replacingOccurrences(of: "completed normally (exit code 0)", with: "exited (exit code 1)").utf8)
    let row = try #require(Transcript(history: try decoder.decode([HistoryRow].self, from: failed)).visible.turns.first)
    #expect(row.agentMessage != nil)
    #expect(row.deliveryFailure?.target == "crew-test")
    #expect(row.deliveryFailure?.headline(for: "Crew Test") == "Message to Crew Test failed.")
}

@Test func recordedAmbiguousAdmissionIsUnconfirmedNotFailed() throws {
    let transcript = Transcript(history: try recorded("crew-test.preview", as: [HistoryRow].self))
    let turn = try #require(transcript.turns.first { $0.prompt?.text == "@crew-test-old hi" })
    guard case .failed(let failure) = mentionExchange(with: "crew-test-old", from: turn.id, in: transcript)?.outcome else { Issue.record("expected an unconfirmed delivery"); return }
    #expect(failure.isUnconfirmed)
    #expect(failure.headline(for: "Crew Peer") == "Delivery to Crew Peer couldn't be confirmed.")
    #expect(failure.explanation(for: "Crew Peer") == nil)
}

@Test func immediateErrorIgnoresReasonsHermesGuessedFromItsOwnText() {
    let refused = ToolCall(name: "message_agent", subject: "", arguments: #"{"target": "balance-bot", "message": "Hi"}"#, result: #"{"error": "No teammate named 'balance-bot'.", "reason": "provider_quota_limit"}"#, status: .error)
    #expect(refused.deliveryFailure == DeliveryFailure(detail: "No teammate named 'balance-bot'.", target: "balance-bot"))
}

@Test func pendingOrTimedOutDeliveryIsUnconfirmed() {
    let head = "[IMPORTANT: Background process proc_51ab completed normally (exit code 0).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery query-file /tmp/dm\nOutput:\n"
    #expect(DeliveryFailure(notice: head + #"{"status": "claimed", "delivery_id": "d1", "detail": "Delivery remains pending or its outcome is unknown. Do not resend."}"# + "\n]")?.isUnconfirmed == true)
    #expect(DeliveryFailure(notice: head + #"{"reply": "Hi!", "status": "settled", "delivery_id": "d1"}"# + "\n]") == nil)
    let timedOut = head.replacingOccurrences(of: "completed normally (exit code 0)", with: "exited (exit code 1)") + "No reply from @scout on mini within 600s. The message may still be delivered when the Desktop reconnects; do not resend blindly.\n]"
    #expect(DeliveryFailure(notice: timedOut)?.isUnconfirmed == true)
}

@Test func lateReplyClearsAnUnconfirmedFollowUp() {
    let start = Date(timeIntervalSince1970: 1_792_136_000)
    let call = ToolCall(name: "message_agent", subject: "", arguments: #"{"target": "scout", "message": "Find flights."}"#, result: #"{"status": "queued", "process_id": "proc_ab12"}"#, status: .success)
    let notice = "[IMPORTANT: Background process proc_ab12 exited (exit code 1).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery --wait-reply /tmp/r.json '@scout on mini' 600\nOutput:\nNo reply from @scout on mini within 600s. The message may still be delivered when the Desktop reconnects; do not resend blindly.\n]"
    let transcript = Transcript(turns: [
        Turn(id: "t1", prompt: Prompt(text: "@scout find flights", sentAt: start), work: [WorkItem(id: "w1", kind: .tool(call), startedAt: start)], status: .complete, startedAt: start),
        Turn(id: "t2", delivery: "proc_ab12", deliveryFailure: DeliveryFailure(notice: notice), status: .complete, startedAt: start.addingTimeInterval(600)),
        Turn(id: "t3", agentMessage: AgentMessage("Message from 🤖 Scout (@scout): Found three flights."), reply: "Scout found three flights.", status: .complete, startedAt: start.addingTimeInterval(700)),
    ])
    let shown = transcript.visible.turns
    #expect(shown.map(\.id) == ["t1", "t3"])
    #expect(shown.allSatisfy { $0.agentMessage == nil && $0.deliveryFailure == nil })
}

@Test func unconfirmedFollowUpWithoutItsOriginStillShows() {
    let start = Date(timeIntervalSince1970: 1_792_136_000)
    let notice = "[IMPORTANT: Background process proc_ab12 exited (exit code 1).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery --wait-reply /tmp/r.json '@scout on mini' 600\nOutput:\nNo reply from @scout on mini within 600s. The message may still be delivered when the Desktop reconnects; do not resend blindly.\n]"
    let transcript = Transcript(turns: [
        Turn(id: "t2", delivery: "proc_ab12", deliveryFailure: DeliveryFailure(notice: notice), status: .complete, startedAt: start),
        Turn(id: "t3", prompt: Prompt(text: "Any news?", sentAt: start.addingTimeInterval(60)), status: .complete, startedAt: start.addingTimeInterval(60)),
    ])
    #expect(transcript.visible.turns.first?.deliveryFailure?.isUnconfirmed == true)
}

@Test func exitZeroWithAFailedStatusIsAFailure() {
    let notice = "[IMPORTANT: Background process proc_51ab completed normally (exit code 0).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery query-file /tmp/dm\nOutput:\n" + #"{"error": "busy", "reason": "target_busy", "status": "failed"}"# + "\nsession_id: 20261022_1\n]"
    #expect(DeliveryFailure(notice: notice) == DeliveryFailure(reason: "target_busy", detail: "busy"))
}
