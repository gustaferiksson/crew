import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

@MainActor @Test func aFirstTurnNeverShowsTheContextCapNoticeAsWorkingText() throws {
    var transcript = Transcript()
    transcript.begin(prompt: "Reply with just: hi")
    let session = ChatSession(fixture: crewTest, transcript: transcript, todos: [])
    let lines = try String(contentsOf: fixtures.appending(path: "chat.first-turn.v0.22.4.jsonl"), encoding: .utf8).split(separator: "\n")

    var shown: [String] = []
    for line in lines {
        session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(line.utf8)))
        if let status = session.statusLine, shown.last != status { shown.append(status) }
    }

    #expect(shown == [])
    #expect(session.transcript.turns.count == 1)
    #expect(session.transcript.turns.last?.work.isEmpty == true)
    #expect(session.transcript.turns.last?.reply == "hi")
}

@MainActor @Test func realCompactionProgressStillShowsAsWorkingText() throws {
    var transcript = Transcript()
    transcript.begin(prompt: "Keep going")
    let session = ChatSession(fixture: crewTest, transcript: transcript, todos: [])
    let event = #"{"payload": {"kind": "compacting", "text": "🗜️ Compacting context — summarizing earlier conversation so I can continue..."}, "seq": 3, "session_id": "rt-1", "type": "status.update"}"#

    session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(event.utf8)))

    #expect(session.statusLine == "🗜️ Compacting context — summarizing earlier conversation so I can continue...")
}
