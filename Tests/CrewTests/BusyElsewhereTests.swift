import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let marlow = Bot(name: "marlow", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

private struct HistoryPage: Decodable {
    let messages: [HistoryRow]
}

private func history() throws -> Transcript {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let page = try decoder.decode(HistoryPage.self, from: Data(contentsOf: fixtures.appending(path: "chat.history.v0.21.7.json")))
    return Transcript(history: page.messages.filter { (62...66).contains($0.id) })
}

private func firstTurn() throws -> [GatewayEvent] {
    let lines = try String(contentsOf: fixtures.appending(path: "chat.first-turn.v0.22.4.jsonl"), encoding: .utf8).split(separator: "\n")
    return try lines.map { try JSONDecoder().decode(GatewayEvent.self, from: Data($0.utf8)) }
}

@MainActor private func openChat() throws -> ChatSession {
    ChatSession(fixture: marlow, transcript: try history(), todos: [], runtime: RuntimeSessionID(rawValue: "rt-1"))
}

@MainActor @Test func aChatWhoseBotWorksElsewhereShowsAWorkingRowUntilTheRosterGoesIdle() throws {
    let session = try openChat()
    let settled = session.visible.turns.count

    session.update(busy: true)
    let working = try #require(session.visible.turns.last)
    #expect(session.visible.turns.count == settled + 1)
    #expect(working.id == Turn.busyElsewhereID && working.status == .streaming && working.prompt == nil)
    #expect(session.transcript.turns.count == settled)

    session.update(busy: false)
    #expect(session.visible.turns.count == settled)
}

@MainActor @Test func aSendWhileTheBotWorksElsewhereWaitsInTheQueueAndGoesOutWhenItIsIdle() throws {
    let session = try openChat()
    let settled = session.transcript.turns.count
    session.update(busy: true)

    session.send("Did Emil answer?", mode: .send)
    #expect(session.transcript.waiting.map(\.pending) == [.queued])
    #expect(session.transcript.turns.count == settled)
    #expect(session.failure == nil)

    session.update(busy: false)
    #expect(session.transcript.waiting.isEmpty)
    #expect(session.transcript.turns.last?.prompt?.text == "Did Emil answer?")
    #expect(session.transcript.turns.last?.status == .streaming)
}

@MainActor @Test func theRosterReportingTheChatsOwnTurnShowsNoWorkingRowAfterItEnds() throws {
    let session = try openChat()
    session.send("Hello", mode: .send)
    session.update(busy: true)
    for event in try firstTurn() { session.apply(event) }
    #expect(!session.isRunning)

    session.update(busy: true)
    #expect(session.visible.turns.last?.id != Turn.busyElsewhereID)

    session.update(busy: false)
    session.update(busy: true)
    #expect(session.visible.turns.last?.id == Turn.busyElsewhereID)
}
