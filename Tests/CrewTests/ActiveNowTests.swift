import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private func recorded<Value: Decodable>(_ path: String, as type: Value.Type, keys: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = keys
    return try decoder.decode(type, from: Data(contentsOf: fixtures.appending(path: path)))
}

@Test func aWorkingBotIsActiveLongAfterItLastWrote() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("scenarios/cold-open/profiles.before.json", as: Roster.self).profiles)
    store.apply(roster: try recorded("scenarios/cold-open/profiles.working.json", as: Roster.self).profiles)
    store.apply(live: try recorded("scenarios/cold-open/active_list.working.json", as: ActiveList.self).sessions)
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    let lastActive = try #require(bot.canonicalSession?.lastActive)

    #expect(ChatSessions().isActive(bot, in: store, at: lastActive.addingTimeInterval(600)))
}

@Test func aReplyKeepsABotActiveForNinetySeconds() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("scenarios/cold-open/profiles.before.json", as: Roster.self).profiles)
    store.apply(roster: try recorded("scenarios/cold-open/profiles.after.json", as: Roster.self).profiles)
    store.apply(live: try recorded("scenarios/cold-open/active_list.after.json", as: ActiveList.self).sessions)
    let rows = try recorded("scenarios/cold-open/crew-test-peer.history.json", as: [HistoryRow].self, keys: .convertFromSnakeCase)
    store.showPreview(of: "crew-test-peer", from: rows)
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    let reply = Date(timeIntervalSince1970: try #require(rows.last).timestamp)
    let chats = ChatSessions()

    #expect(store.statuses["crew-test-peer"] == .unread)
    #expect(chats.isActive(bot, in: store, at: reply.addingTimeInterval(60)))
    #expect(chats.isActive(bot, in: store, at: reply.addingTimeInterval(89)))
    #expect(!chats.isActive(bot, in: store, at: reply.addingTimeInterval(120)))
}

@Test func aWorkerHeartbeatKeepsABotActiveFor150Seconds() throws {
    var bot = try #require(try recorded("profiles.list.v0.21.7.json", as: Roster.self).profiles.first { $0.name == "default" })
    let store = BotStore(fixture: [bot], statuses: [:])
    let now = try #require(bot.canonicalSession?.lastActive).addingTimeInterval(600)

    #expect(bot.workerActive == Date(timeIntervalSince1970: 1791878658.7783456))
    #expect(!ChatSessions().isActive(bot, in: store, at: now))
    bot.workerActive = now.addingTimeInterval(-120)
    #expect(ChatSessions().isActive(bot, in: store, at: now))
    bot.workerActive = now.addingTimeInterval(-160)
    #expect(!ChatSessions().isActive(bot, in: store, at: now))
}
