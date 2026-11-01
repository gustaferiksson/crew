import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

@MainActor @Test(arguments: ["chat.steer-answer-after-tools-turn.jsonl", "chat.tool-turn.v0.21.7.jsonl", "chat.think-turn.v0.22.2.jsonl"])
func theStoredVisibleTranscriptFollowsEveryEvent(recording: String) throws {
    var start = Transcript()
    start.begin(prompt: "Run step one, then tell me what you found.")
    let session = ChatSession(fixture: crewTest, transcript: start, todos: [])
    #expect(session.visible == session.transcript.visible)
    let events = try String(contentsOf: fixtures.appending(path: recording), encoding: .utf8).split(separator: "\n")
        .map { try JSONDecoder().decode(GatewayEvent.self, from: Data($0.utf8)) }
    for event in events {
        session.apply(event)
        #expect(session.visible == session.transcript.visible, "after \(event.type)")
    }
    #expect(session.visible.turns.last?.reply.isEmpty == false)
}
