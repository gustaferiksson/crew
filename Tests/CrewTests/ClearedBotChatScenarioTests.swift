import Foundation
import Testing

private let scenarios = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios")
private let chat = "20261017_091102_71c52a"

private func roster(_ scenario: String, messages: Int? = nil, marker: Int?? = nil, session: String = chat) throws -> [Bot] {
    let data = try Data(contentsOf: scenarios.appending(path: "\(scenario)/profiles.after.json"))
    var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var profiles = try #require(json["profiles"] as? [[String: Any]])
    let index = try #require(profiles.firstIndex { $0["name"] as? String == "vera" })
    var canonical = try #require(profiles[index]["canonical_session"] as? [String: Any])
    if let messages { canonical["message_count"] = messages }
    canonical["resolved_id"] = session
    profiles[index]["canonical_session"] = canonical
    var meta = try #require(profiles[index]["ui_meta"] as? [String: Any])
    if let marker { meta["crew"] = marker.map { ["session": chat, "messages": $0] } }
    profiles[index]["ui_meta"] = meta
    json["profiles"] = profiles
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(Roster.self, from: JSONSerialization.data(withJSONObject: json)).profiles
}

private func vera(_ store: BotStore) throws -> Bot {
    try #require(store.bots.first { $0.name == "vera" })
}

private func readBeforeTheClear(marker: Int?? = nil) throws -> BotStore {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try roster("untitled-bot-chat", marker: marker))
    store.apply(live: [])
    #expect(store.statuses["vera"] == nil)
    return store
}

@Test func clearedBotChatWithANewReplyIsUnreadUntilViewed() throws {
    let store = try readBeforeTheClear()
    store.apply(roster: try roster("cleared-bot-chat"))
    store.apply(live: [])
    let bot = try vera(store)
    #expect(bot.readPosition == ReadPosition(session: chat, messages: 17))
    #expect(bot.canonicalSession?.position == ReadPosition(session: chat, messages: 2))
    #expect(bot.lastRead == ReadPosition(session: chat, messages: 0))
    #expect(store.statuses["vera"] == .unread)
    #expect(store.sections.first?.bots.first?.name == "vera")

    store.markSeen(bot)
    #expect(store.statuses["vera"] == nil)

    store.apply(roster: try roster("cleared-bot-chat", messages: 4, marker: 2))
    store.apply(live: [])
    #expect(store.statuses["vera"] == .unread)
}

@Test func clearedMarkerIsRewrittenToTheSessionStartWithoutAView() throws {
    let bot = try #require(try roster("cleared-bot-chat").first { $0.name == "vera" })
    #expect(bot.needsMarker(at: ReadPosition(session: chat, messages: 0)))
    #expect(bot.needsMarker(at: ReadPosition(session: chat, messages: 2)))
    #expect(!bot.needsMarker(at: ReadPosition(session: chat, messages: 17)))
    #expect(!bot.needsMarker(at: ReadPosition(session: chat, messages: 18)))

    let viewed = try #require(try roster("cleared-bot-chat", messages: 4, marker: 2).first { $0.name == "vera" })
    #expect(!viewed.needsMarker(at: ReadPosition(session: chat, messages: 0)))
    #expect(viewed.needsMarker(at: ReadPosition(session: chat, messages: 4)))

    let store = try readBeforeTheClear()
    store.apply(roster: try roster("cleared-bot-chat", messages: 17, marker: 0))
    store.apply(live: [])
    #expect(store.statuses["vera"] == .unread)
}

@Test func clearedBotChatWithNoRowsIsNotUnread() throws {
    let store = try readBeforeTheClear()
    store.apply(roster: try roster("cleared-bot-chat", messages: 0))
    store.apply(live: [])
    #expect(store.statuses["vera"] == nil)
}

@Test func clearedBotChatWithoutAMarkerIsUnread() throws {
    let store = try readBeforeTheClear(marker: .some(nil))
    #expect(try vera(store).readPosition == nil)
    store.apply(roster: try roster("cleared-bot-chat", marker: .some(nil)))
    store.apply(live: [])
    #expect(store.statuses["vera"] == .unread)
}

@Test func compactionTipIsNotAClear() throws {
    let tip = try #require(try roster("cleared-bot-chat", session: "20261017_120000_abcdef").first { $0.name == "vera" })
    #expect(tip.lastRead == tip.readPosition)
    #expect(!tip.needsMarker(at: ReadPosition(session: chat, messages: 0)))
}
