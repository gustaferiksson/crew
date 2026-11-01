import Foundation
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/start-new-chat")
private let retired = StoredSessionID(rawValue: "20261017_102454_92b952")
private let fresh = StoredSessionID(rawValue: "20261101_183133_54935c")

private func recorded<Value: Decodable>(_ name: String, as type: Value.Type, keys: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = keys
    return try decoder.decode(type, from: Data(contentsOf: scenario.appending(path: "\(name).json")))
}

@Test func startNewChatUnhidesThenRetitlesThenArchivesTheRuntimeOverTheGateway() throws {
    let steps = botChatRetirement(of: RuntimeSessionID(rawValue: "a1b2c3"), at: Date(timeIntervalSince1970: 1_793_000_000))
    #expect(steps.map(\.method) == ["session.set_hidden", "session.title", "session.archive"])
    #expect(steps.allSatisfy { $0.params["session_id"] == .string("a1b2c3") })
    #expect(steps[0].params["hidden"] == .bool(false))
    #expect(steps[2].params["archived"] == .bool(true))
    guard case .string(let title) = steps[1].params["title"] else { Issue.record("no title"); return }
    #expect(title.hasPrefix("Bot Chat until "))
    #expect(!title.contains("#"))
}

@Test func startNewChatMovesTheBotRowToTheFreshChat() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.before", as: Roster.self).profiles)
    #expect(store.bots.first { $0.name == "crew-test" }?.canonicalSession?.id == retired)

    store.apply(roster: try recorded("profiles.retired", as: Roster.self).profiles)
    let empty = try #require(store.bots.first { $0.name == "crew-test" }?.canonicalSession)
    #expect(empty.id == fresh)
    #expect(empty.messageCount == 0)

    store.apply(roster: try recorded("profiles.after", as: Roster.self).profiles)
    store.showPreview(of: "crew-test", from: try recorded("crew-test.preview", as: [HistoryRow].self, keys: .convertFromSnakeCase))
    let bot = try #require(store.bots.first { $0.name == "crew-test" })
    #expect(bot.canonicalSession?.id == fresh)
    #expect(ChatSessions().summary(of: bot, in: store).preview == "fresh-start")
}
