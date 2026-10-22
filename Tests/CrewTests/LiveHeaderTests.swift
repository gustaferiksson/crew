import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

private struct Offset: Decodable {
    let at: TimeInterval
}

@MainActor @Test func theLiveHeaderKeepsItsDotsUntilTheReplyStartsThenSettles() throws {
    var transcript = Transcript()
    transcript.begin(prompt: "Think it through, then use your terminal tool to count the files in your current directory, and answer in one sentence.")
    let session = ChatSession(fixture: crewTest, transcript: transcript, todos: [])
    let lines = try String(contentsOf: fixtures.appending(path: "chat.think-turn.v0.22.2.jsonl"), encoding: .utf8).split(separator: "\n")

    var header: [String] = []
    for line in lines {
        let data = Data(line.utf8)
        let at = try JSONDecoder().decode(Offset.self, from: data).at
        session.apply(try JSONDecoder().decode(GatewayEvent.self, from: data))
        guard let turn = session.transcript.turns.last else { continue }
        let state = turn.status != .streaming ? "worked" : turn.reply.isEmpty ? "working, dots" : "working"
        if header.last?.components(separatedBy: " from ").first != state { header.append("\(state) from \(at)") }
    }

    #expect(header == ["working, dots from 0.022", "working from 15.35", "worked from 15.798"])
    #expect(session.transcript.turns.last?.work.count == 1)
    #expect(session.transcript.turns.last?.reply.hasPrefix("I can’t count the files") == true)
}

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

@MainActor @Test func realCompactionProgressStillShowsAsWorkingTextPastAnInfoDiagnostic() throws {
    var transcript = Transcript()
    transcript.begin(prompt: "Keep going")
    let session = ChatSession(fixture: crewTest, transcript: transcript, todos: [])
    let event = #"{"payload": {"kind": "compacting", "text": "🗜️ Compacting context — summarizing earlier conversation so I can continue..."}, "seq": 3, "session_id": "rt-1", "type": "status.update"}"#

    let diagnostic = #"{"payload": {"kind": "warn", "text": "ℹ️ Estimated cost of these empty attempts: ~$0.02"}, "seq": 4, "session_id": "rt-1", "type": "status.update"}"#

    session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(event.utf8)))
    session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(diagnostic.utf8)))

    #expect(session.statusLine == "🗜️ Compacting context — summarizing earlier conversation so I can continue...")
}
