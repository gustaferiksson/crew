import Foundation
import Testing

private let liveRows = """
[
  {"id": 1, "role": "user", "content": "Message from 🤖 Crew Test (@crew-test): The user is greeting you—please say hello back.", "timestamp": 1792092581.7, "display_kind": "internal_notification"},
  {"id": 4, "role": "assistant", "content": "Hello!", "timestamp": 1792092590.1}
]
"""

@Test func historyRowFromAnotherBotBecomesANoticeWithItsReply() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([HistoryRow].self, from: Data(liveRows.utf8))
    let turns = Transcript(history: rows).turns
    #expect(turns.count == 1)
    #expect(turns[0].prompt == nil)
    #expect(turns[0].notice == "Message from Crew Test")
    #expect(turns[0].agentMessage?.handle == "crew-test")
    #expect(turns[0].agentMessage?.body == "The user is greeting you—please say hello back.")
    #expect(turns[0].reply == "Hello!")
}

@Test func liveRemotePromptFromAnotherBotBecomesANotice() {
    var transcript = Transcript()
    transcript.begin(remote: "Message from 🤖 Scout (@scout): Flights found.", displayKind: "internal_notification", at: .now)
    #expect(transcript.turns.last?.prompt == nil)
    #expect(transcript.turns.last?.agentMessage == AgentMessage("Message from Scout (@scout): Flights found."))
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
