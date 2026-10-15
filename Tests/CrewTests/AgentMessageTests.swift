import Foundation
import Testing

private let liveRows = """
[
  {"id": 1, "role": "user", "content": "Message from 🤖 Crew Test (@crew-test): The user is greeting you—please say hello back.", "timestamp": 1792092581.7, "display_kind": "internal_notification"},
  {"id": 2, "role": "assistant", "content": "", "tool_calls": [{"id": "call_220ec837e8ef4d44898d5cd62dfb2dd1", "function": {"name": "message_agent", "arguments": "{\\"target\\":\\"crew-test\\",\\"message\\":\\"Hello! Please pass my greeting along to the user.\\"}"}}], "timestamp": 1792092586.7},
  {"id": 3, "role": "tool", "content": "{\\"status\\": \\"ambiguous\\"}", "tool_call_id": "call_220ec837e8ef4d44898d5cd62dfb2dd1", "timestamp": 1792092586.8},
  {"id": 4, "role": "assistant", "content": "Hello!", "timestamp": 1792092590.1},
  {"id": 5, "role": "user", "content": "What did Crew Test say?", "timestamp": 1792092600.0},
  {"id": 6, "role": "assistant", "content": "Just hello.", "timestamp": 1792092605.0}
]
"""

@Test func historyHidesTheWholeTurnFromAnotherBot() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([HistoryRow].self, from: Data(liveRows.utf8))
    let transcript = Transcript(history: rows)
    #expect(transcript.turns.count == 2)
    #expect(transcript.turns[0].agentMessage?.handle == "crew-test")
    #expect(transcript.turns[0].agentMessage?.body == "The user is greeting you—please say hello back.")
    #expect(transcript.turns[0].reply == "Hello!")
    #expect(transcript.turns[0].work.count == 1)
    #expect(transcript.visible.turns.map(\.id) == ["5"])
    #expect(transcript.visible.turns[0].reply == "Just hello.")
}

@Test func liveTurnFromAnotherBotStaysHidden() {
    var transcript = Transcript()
    transcript.begin(prompt: "Plan the trip", at: .now)
    transcript.apply(.messageComplete(text: "On it.", status: .complete, error: nil))
    transcript.begin(remote: "Message from 🤖 Scout (@scout): Flights found.", displayKind: "internal_notification", at: .now)
    transcript.apply(.messageStart)
    transcript.apply(.messageDelta("Thanks, Scout."))
    #expect(transcript.turns.count == 2)
    #expect(transcript.turns.last?.agentMessage == AgentMessage("Message from Scout (@scout): Flights found."))
    #expect(transcript.turns.last?.reply == "Thanks, Scout.")
    #expect(transcript.visible.turns.map(\.reply) == ["On it."])
}

@Test func agentMessageFormsMatchDesktop() {
    let relayed = AgentMessage("Message from Ada (@ada@studio):\nMultiline\nbody")
    #expect(relayed?.sender == "Ada")
    #expect(relayed?.handle == "ada")
    #expect(relayed?.body == "Multiline\nbody")
    let legacy = AgentMessage("[Message from agent 'scout'] Done.")
    #expect(legacy?.sender == "scout")
    #expect(legacy?.handle == "scout")
    #expect(legacy?.body == "Done.")
    #expect(AgentMessage("Message from Hermes: hi")?.handle == "default")
    #expect(AgentMessage("Message from the team was great") == nil)
    #expect(AgentMessage("Hey, are you up?") == nil)
}
