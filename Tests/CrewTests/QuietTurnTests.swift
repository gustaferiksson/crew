import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

private struct Offset: Decodable {
    let at: TimeInterval
}

private func timedEvents() throws -> [(at: TimeInterval, event: GatewayEvent)] {
    let lines = try String(contentsOf: fixtures.appending(path: "chat.think-turn.v0.22.2.jsonl"), encoding: .utf8).split(separator: "\n")
    return try lines.map { line in
        let data = Data(line.utf8)
        return (try JSONDecoder().decode(Offset.self, from: data).at, try JSONDecoder().decode(GatewayEvent.self, from: data))
    }
}

@MainActor @Test func theDotsShowWhileTheBotIsSilentAndGiveWayToEachItem() throws {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    var transcript = Transcript()
    transcript.begin(prompt: "Think it through, then use your terminal tool to count the files in your current directory, and answer in one sentence.", at: start)
    let session = ChatSession(fixture: crewTest, transcript: transcript, todos: [])

    var changes: [String] = []
    var shown = false
    for (at, event) in try timedEvents() {
        let date = start.addingTimeInterval(at)
        let before = session.transcript.turns.last?.isQuiet(at: date) == true
        if before != shown { changes.append("\(before ? "dots" : "none") by \(event.type) at \(at)") }
        session.apply(event, at: date)
        shown = session.transcript.turns.last?.isQuiet(at: date) == true
        if shown != before { changes.append("\(shown ? "dots" : "none") after \(event.type) at \(at)") }
    }

    #expect(changes == [
        "dots by message.start at 0.022",
        "none after tool.start at 7.184",
        "dots by sessions.changed at 13.596",
        "none after message.delta at 15.35",
    ])
    #expect(session.transcript.turns.last?.reply.hasPrefix("I can’t count the files") == true)
}

@Test func aQuickToolBatchNeverFlashesTheDots() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    var transcript = Transcript()
    transcript.begin(prompt: "Read both files", at: start)
    #expect(transcript.turns[0].isQuiet(at: start))

    transcript.apply(.toolStart(id: "a", name: "read_file", context: nil, arguments: "{}"), at: start.addingTimeInterval(1))
    #expect(!transcript.turns[0].isQuiet(at: start.addingTimeInterval(5)))

    transcript.apply(.toolComplete(id: "a", duration: 1, summary: nil, result: "{}"), at: start.addingTimeInterval(2))
    #expect(transcript.turns[0].quietSince == start.addingTimeInterval(2))
    #expect(!transcript.turns[0].isQuiet(at: start.addingTimeInterval(3.9)))
    #expect(transcript.turns[0].isQuiet(at: start.addingTimeInterval(4)))

    transcript.apply(.toolStart(id: "b", name: "read_file", context: nil, arguments: "{}"), at: start.addingTimeInterval(3))
    #expect(!transcript.turns[0].isQuiet(at: start.addingTimeInterval(9)))

    transcript.apply(.toolComplete(id: "b", duration: 1, summary: nil, result: "{}"), at: start.addingTimeInterval(4))
    transcript.apply(.messageDelta("Both files are"), at: start.addingTimeInterval(5))
    #expect(!transcript.turns[0].isQuiet(at: start.addingTimeInterval(9)))

    transcript.apply(.messageComplete(text: "Both files are empty.", status: .complete, error: nil), at: start.addingTimeInterval(6))
    #expect(transcript.turns[0].quietSince == nil)
}

@Test func aStalledThinkingRowGetsTheDotsButAnotherBotsTurnNever() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    var transcript = Transcript()
    transcript.begin(prompt: "Plan the trip", at: start)
    transcript.apply(.reasoningDelta("Checking the ferry times first."), at: start.addingTimeInterval(1))
    #expect(!transcript.turns[0].isQuiet(at: start.addingTimeInterval(2.9)))
    #expect(transcript.turns[0].isQuiet(at: start.addingTimeInterval(3)))

    transcript.begin(remote: "Message from 🤖 Scout (@scout): Can you add the ferry?", displayKind: nil, at: start)
    #expect(transcript.turns[1].quietSince == nil)
}
