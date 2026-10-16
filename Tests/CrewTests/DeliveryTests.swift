import Foundation
import Testing

private let senderRows = #"""
[
 {"id": 316, "role": "user", "content": "@test-bot hi\n\n[@mentions resolved from the Bot Mode roster — the user is referring to: @test-bot = agent profile \"test-bot\" (\"Test bot\"). If they want one of these agents contacted, compose your own message and send it with your message_agent tool (agents on other connected machines are reachable too — the Desktop relays it); never forward the user’s text verbatim. If this session has no message_agent tool, agent messaging is unavailable here — say so.]", "timestamp": 1792127258.239412, "display_kind": null},
 {"id": 317, "role": "assistant", "content": "", "timestamp": 1792127263.8912752, "display_kind": null, "tool_calls": [{"id": "call_c5a0863634ca468eab286de7aaca56bf", "function": {"name": "message_agent", "arguments": "{\"target\":\"test-bot\",\"message\":\"The user sends another greeting; please say hello back.\"}"}}]},
 {"id": 318, "role": "tool", "content": "{\"status\": \"queued\", \"delivery_id\": \"db80e764edb6ca389c727f87319c77bc9cdfd8dc8f0f976e56ea84941836de81\", \"to\": \"@test-bot\", \"reply_delivery\": \"notification\", \"detail\": \"Message queued for @test-bot: this acknowledges the hand-off to a background delivery process, not a delivery receipt \\u2014 do NOT wait or poll. Finish your turn now; that process's completion notification carries the delivery outcome \\u2014 the reply (relay it then, attributed to that agent) or the delivery failure (report it; the message was NOT delivered).\", \"process_id\": \"proc_8df9ddaf2d55\", \"queued_at\": 1792127264}", "timestamp": 1792127264.1259928, "display_kind": null, "tool_call_id": "call_c5a0863634ca468eab286de7aaca56bf"},
 {"id": 319, "role": "assistant", "content": "Your greeting is queued for @test-bot.", "timestamp": 1792127267.6096509, "display_kind": null},
 {"id": 320, "role": "user", "content": "Message from 🤖 Test bot (@test-bot): Hello again! 👋", "timestamp": 1792127285.0400348, "display_kind": null},
 {"id": 321, "role": "assistant", "content": "@test-bot replied: “Hello again! 👋”", "timestamp": 1792127287.640449, "display_kind": null},
 {"id": 322, "role": "user", "content": "[IMPORTANT: Background process proc_8df9ddaf2d55 completed normally (exit code 0).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery --author '{\"id\":\"bot:crew-test\",\"name\":\"crew-test\",\"is_bot\":true}' query-file /opt/data/cache/scratch/hermes-dm-10000/dm-wvts_80m.txt --profile-home /opt/data/profiles/test-bot /opt/hermes/.venv/bin/hermes -p test-bot chat --in '~' -c 'Bot Chat' --create-if-missing -Q\nOutput:\nCrew Test confirmed receipt of my greeting.\n↻ Resumed session local-2f019da0d42e7edb4df0ce4f8deecfcd9b642a429ec33508ac38d156e26d39b8 \"Bot Chat\" (1 user message, 4 total messages)\n↻ Working directory: /opt/data/profiles/test-bot\n\nsession_id: local-2f019da0d42e7edb4df0ce4f8deecfcd9b642a429ec33508ac38d156e26d39b8\n]", "timestamp": 1792127293.1281185, "display_kind": "process_complete"},
 {"id": 323, "role": "assistant", "content": "@test-bot replied, “Hello again! 👋”; the background delivery process has now finished successfully.", "timestamp": 1792127300.5223527, "display_kind": null}
]
"""#

private let targetRows = #"""
[
 {"id": 5, "role": "user", "content": "Message from 🤖 Crew Test (@crew-test): The user sends another greeting; please say hello back.", "timestamp": 1792127276.3425496, "display_kind": null},
 {"id": 6, "role": "assistant", "content": "", "timestamp": 1792127281.3490593, "display_kind": null, "tool_calls": [{"id": "call_23d3f988f9c940aaa4fbe51fabec401d", "function": {"name": "message_agent", "arguments": "{\"target\":\"crew-test\",\"message\":\"Hello again! 👋\"}"}}]},
 {"id": 7, "role": "tool", "content": "{\"status\": \"queued\", \"delivery_id\": \"27a55319beabddaa4793da7d10dc769533227db9af9ca5ae10e902033595032c\", \"to\": \"@crew-test\", \"detail\": \"Durably queued for the live Bot Chat owner. Do NOT wait or resend; finish your turn.\", \"process_id\": \"proc_747c697fd2e6\", \"reply_delivery\": \"notification\"}", "timestamp": 1792127281.529329, "display_kind": null, "tool_call_id": "call_23d3f988f9c940aaa4fbe51fabec401d"},
 {"id": 8, "role": "assistant", "content": "Hello again! 👋", "timestamp": 1792127283.611511, "display_kind": null},
 {"id": 9, "role": "user", "content": "[IMPORTANT: Background process proc_747c697fd2e6 completed normally (exit code 0).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery --author '{\"id\":\"bot:test-bot\",\"name\":\"test-bot\",\"is_bot\":true}' query-file /opt/data/profiles/test-bot/cache/scratch/hermes-dm-10000/dm-64as2zv6.txt --profile-home /opt/data/profiles/crew-test /opt/hermes/.venv/bin/hermes -p crew-test chat --in '~' -c 'Bot Chat' --create-if-missing -Q\nOutput:\n{\"reply\": \"@test-bot replied: \\u201cHello again! \\ud83d\\udc4b\\u201d\", \"status\": \"settled\", \"delivery_id\": \"27a55319beabddaa4793da7d10dc769533227db9af9ca5ae10e902033595032c\"}\n]", "timestamp": 1792127287.7407491, "display_kind": null},
 {"id": 10, "role": "assistant", "content": "Crew Test confirmed receipt of my greeting.", "timestamp": 1792127292.1401896, "display_kind": null}
]
"""#

private func transcript(_ json: String) throws -> Transcript {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return Transcript(history: try decoder.decode([HistoryRow].self, from: Data(json.utf8)))
}

@Test func senderKeepsTheRelayButNotTheDeliveryNotice() throws {
    let visible = try transcript(senderRows).visible
    #expect(visible.turns.map(\.id) == ["316", "322"])
    #expect(visible.turns[1].delivery == "proc_8df9ddaf2d55")
    #expect(visible.turns[1].prompt == nil)
    #expect(visible.turns[1].notice == nil)
    #expect(visible.turns[1].reply == "@test-bot replied, “Hello again! 👋”; the background delivery process has now finished successfully.")
    #expect(try transcript(senderRows).preview == "@test-bot replied, “Hello again! 👋”; the background delivery process has now finished successfully.")
}

@Test func targetHidesTheDeliveryTurnOfItsHiddenExchange() throws {
    let target = try transcript(targetRows)
    #expect(target.turns.map(\.delivery) == [nil, "proc_747c697fd2e6"])
    #expect(target.turns[1].prompt == nil)
    #expect(target.visible.turns.isEmpty)
    #expect(target.preview == nil)
}

@Test func otherBackgroundProcessesKeepTheirNotice() throws {
    let rows = #"[{"id": 1, "role": "user", "content": "[IMPORTANT: Background process proc_51479e2ce84d completed normally (exit code 0).\nCommand: sleep 5\nOutput:\n]", "timestamp": 1, "display_kind": "process_complete"}]"#
    let turn = try transcript(rows).visible.turns.first
    #expect(turn?.delivery == nil)
    #expect(turn?.notice == "Background process finished")
}

@Test func liveDeliveryFollowsItsOrigin() {
    let result = #"{"status": "queued", "process_id": "proc_8df9ddaf2d55"}"#
    let notice = "[IMPORTANT: Background process proc_8df9ddaf2d55 completed normally (exit code 0).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery --author x\n]"
    var transcript = Transcript()
    transcript.begin(prompt: "@test-bot hi", at: .now)
    transcript.apply(.toolStart(id: "c1", name: "message_agent", context: nil, arguments: "{}"))
    transcript.apply(.toolComplete(id: "c1", duration: nil, summary: nil, result: result))
    transcript.apply(.messageComplete(text: "Sent.", status: .complete, error: nil))
    transcript.begin(remote: notice, displayKind: "process_complete", at: .now)
    transcript.apply(.messageDelta("@test-bot replied: Hello!"))
    #expect(transcript.visible.turns.map(\.reply) == ["Sent.", "@test-bot replied: Hello!"])
    #expect(transcript.visible.turns.last?.notice == nil)
    transcript.turns[0].agentMessage = AgentMessage("Message from Scout (@scout): hi")
    #expect(transcript.visible.turns.isEmpty)
}

@Test func historyDropsTheWholeMentionNote() {
    let bot = Bot(name: "test-bot", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta(title: "Test bot"))
    let note = mentionNote(for: [bot])
    #expect(note.contains("relay the reply in one line"))
    #expect(Prompt(raw: "@test-bot hi" + note, sentAt: .now).text == "@test-bot hi")
}

@Test func deliveryWithoutLoadedOriginShowsOnlyBesideAUserTurn() throws {
    let rows = try JSONSerialization.jsonObject(with: Data(senderRows.utf8)) as? [[String: Any]] ?? []
    let user: [String: Any] = ["id": 300, "role": "user", "content": "Plan the trip", "timestamp": 1792127200.0]
    let alone = try JSONSerialization.data(withJSONObject: Array(rows.suffix(2)))
    let beside = try JSONSerialization.data(withJSONObject: [user] + rows.suffix(2))
    #expect(try transcript(String(decoding: alone, as: UTF8.self)).visible.turns.isEmpty)
    let visible = try transcript(String(decoding: beside, as: UTF8.self)).visible
    #expect(visible.turns.map(\.id) == ["300", "322"])
    #expect(visible.turns[1].prompt == nil)
}

@Test func targetWindowCutAtADeliveryHasNoPreview() throws {
    let rows = #"""
    [
     {"id": 9, "role": "user", "content": "[IMPORTANT: Background process proc_747c697fd2e6 completed normally (exit code 0).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery --author '{\"id\":\"bot:test-bot\",\"name\":\"test-bot\",\"is_bot\":true}' query-file /opt/data/profiles/test-bot/cache/scratch/hermes-dm-10000/dm-64as2zv6.txt --profile-home /opt/data/profiles/crew-test /opt/hermes/.venv/bin/hermes -p crew-test chat --in '~' -c 'Bot Chat' --create-if-missing -Q\nOutput:\n{\"reply\": \"@test-bot replied: \\u201cHello again! \\ud83d\\udc4b\\u201d\", \"status\": \"settled\", \"delivery_id\": \"27a55319beabddaa4793da7d10dc769533227db9af9ca5ae10e902033595032c\"}\n]", "timestamp": 1792127287.7407491, "display_kind": null},
     {"id": 10, "role": "assistant", "content": "Crew Test confirmed receipt of my greeting.", "timestamp": 1792127292.1401896, "display_kind": null},
     {"id": 11, "role": "user", "content": "Message from 🤖 Crew Test (@crew-test): The user is saying hello to you again; please return a brief greeting.", "timestamp": 1792128776.9626284, "display_kind": null},
     {"id": 12, "role": "assistant", "content": "", "timestamp": 1792128780.5112712, "display_kind": null, "tool_calls": [{"id": "call_4abd74874a61445388e0d82da3dd3da7", "function": {"name": "message_agent", "arguments": "{\"target\":\"crew-test\",\"message\":\"Hello again! 👋\"}"}}]},
     {"id": 13, "role": "tool", "content": "{\"status\": \"queued\", \"delivery_id\": \"e4d07c453a585a82bec61d0e320bfecc6435751d440aa063697523b3570402a1\", \"to\": \"@crew-test\", \"detail\": \"Durably queued for the live Bot Chat owner. Do NOT wait or resend; finish your turn.\", \"process_id\": \"proc_cacfa982ae01\", \"reply_delivery\": \"notification\"}", "timestamp": 1792128780.7004855, "display_kind": null, "tool_call_id": "call_4abd74874a61445388e0d82da3dd3da7"},
     {"id": 14, "role": "assistant", "content": "Hello again! 👋", "timestamp": 1792128782.3444617, "display_kind": null},
     {"id": 15, "role": "user", "content": "[IMPORTANT: Background process proc_cacfa982ae01 completed normally (exit code 0).\nCommand: /opt/hermes/.venv/bin/python /opt/hermes/tools/bot_mode_dm.py --run-delivery --author '{\"id\":\"bot:test-bot\",\"name\":\"test-bot\",\"is_bot\":true}' query-file /opt/data/profiles/test-bot/cache/scratch/hermes-dm-10000/dm-n_780749.txt --profile-home /opt/data/profiles/crew-test /opt/hermes/.venv/bin/hermes -p crew-test chat --in '~' -c 'Bot Chat' --create-if-missing -Q\nOutput:\n{\"reply\": \"@test-bot: Hello again! \\ud83d\\udc4b\", \"status\": \"settled\", \"delivery_id\": \"e4d07c453a585a82bec61d0e320bfecc6435751d440aa063697523b3570402a1\"}\n]", "timestamp": 1792128787.4068782, "display_kind": null},
     {"id": 16, "role": "assistant", "content": "Crew Test received my greeting.", "timestamp": 1792128789.9351559, "display_kind": null}
    ]
    """#
    #expect(try transcript(rows).visible.turns.isEmpty)
    #expect(try transcript(rows).preview == nil)
}
