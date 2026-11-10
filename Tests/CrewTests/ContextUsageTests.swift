import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/usage")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

private struct Breakdown: Decodable {
    let categories: [ContextCategory]
}

@MainActor @Test func aRealTurnFillsTheContextRingFromItsCompletionUsage() throws {
    var transcript = Transcript()
    transcript.begin(prompt: "Reply with just: ok")
    let session = ChatSession(fixture: crewTest, transcript: transcript, todos: [])
    let lines = try String(contentsOf: fixtures.appending(path: "usage-turn.v0.23.0.jsonl"), encoding: .utf8).split(separator: "\n")

    #expect(session.context == nil)
    for line in lines {
        session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(line.utf8)))
    }

    #expect(session.context == ContextUsage(used: 21_987, window: 500_000))
    #expect(session.context?.isHigh == false)
}

@Test func aResumedChatCarriesItsContextInTheSnapshotInfo() throws {
    let snapshot = try JSONDecoder().decode(LiveSnapshot.self, from: Data(contentsOf: fixtures.appending(path: "session.resume.v0.23.0.json")))

    #expect(snapshot.info?.usage == ContextUsage(used: 21_971, window: 500_000))
}

@Test func aFreshChatWithoutAContextWindowShowsNoRing() throws {
    let snapshot = try JSONDecoder().decode(LiveSnapshot.self, from: Data(#"{"session_id":"s1","info":{"usage":{"calls":0,"input":0,"output":0,"total":0}}}"#.utf8))
    let zeroWindow = try? JSONDecoder().decode(ContextUsage.self, from: Data(#"{"context_used":0,"context_max":0}"#.utf8))

    #expect(snapshot.info?.usage == nil)
    #expect(zeroWindow == nil)
}

@MainActor @Test func aUsageTickWithoutContextFieldsKeepsTheKnownContext() throws {
    let session = ChatSession(fixture: crewTest, transcript: Transcript(), todos: [], context: ContextUsage(used: 21_971, window: 500_000))

    session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(#"{"type":"session.usage","session_id":"s1","payload":{"usage":{"calls":1,"input":10,"output":2,"total":12}}}"#.utf8)))

    #expect(session.context == ContextUsage(used: 21_971, window: 500_000))
}

@Test func theRealBreakdownListsHermesCategories() throws {
    let breakdown = try JSONDecoder().decode(Breakdown.self, from: Data(contentsOf: fixtures.appending(path: "session.context_breakdown.v0.23.0.json")))

    #expect(breakdown.categories.map(\.label) == ["System prompt", "Tool definitions", "Conversation"])
    #expect(breakdown.categories.map(\.tokens).allSatisfy { $0 > 0 })
}

@Test func usageTurnsHighAtFortyPercentOfTheWindow() {
    #expect(ContextUsage(used: 399_999, window: 1_000_000).isHigh == false)
    #expect(ContextUsage(used: 400_000, window: 1_000_000).isHigh)
    #expect(ContextUsage(used: 1_200_000, window: 1_000_000).fraction == 1)
}

@MainActor @Test func afterCompactTheRingReadsHermesFreshEstimateInsteadOfTheStaleUsage() throws {
    let reply = fixtures.appending(path: "\(ChatSession.compactedContextMethod).after-compact.v0.23.0.json")

    let context = try JSONDecoder().decode(ContextUsage.self, from: Data(contentsOf: reply))

    #expect(context == ContextUsage(used: 16_492, window: 500_000))
}
