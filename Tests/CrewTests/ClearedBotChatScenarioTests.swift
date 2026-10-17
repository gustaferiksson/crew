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

private func live(_ status: String) throws -> [LiveSession] {
    let data = try Data(contentsOf: scenarios.appending(path: "cleared-bot-chat/active_list.after.json"))
    var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    json["sessions"] = try #require(json["sessions"] as? [[String: Any]]).map { $0.merging(["status": status]) { $1 } }
    return try JSONDecoder().decode(ActiveList.self, from: JSONSerialization.data(withJSONObject: json)).sessions
}

private func vera(in bots: [Bot]) throws -> Bot {
    try #require(bots.first { $0.name == "vera" })
}

private func readBeforeTheDrop(marker: Int?? = nil) throws -> BotStore {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try roster("untitled-bot-chat", marker: marker))
    store.apply(live: [])
    #expect(store.statuses["vera"] == nil)
    return store
}

private func step(_ store: BotStore, messages: Int, marker: Int?? = nil, live status: String = "idle") throws -> BotStatus? {
    store.apply(roster: try roster("cleared-bot-chat", messages: messages, marker: marker))
    store.apply(live: try live(status))
    return store.statuses["vera"]
}

@Test func droppedCountReadsAsReadAtTheCurrentCount() throws {
    let bot = try vera(in: try roster("cleared-bot-chat"))
    #expect(bot.readPosition == ReadPosition(session: chat, messages: 17))
    #expect(bot.lastRead == ReadPosition(session: chat, messages: 2))
    #expect(bot.needsMarker(at: ReadPosition(session: chat, messages: 2)))
    #expect(!bot.needsMarker(at: ReadPosition(session: chat, messages: 0)))
    #expect(!bot.needsMarker(at: ReadPosition(session: chat, messages: 18)))
    let rebaselined = try vera(in: try roster("cleared-bot-chat", marker: 2))
    #expect(!rebaselined.needsMarker(at: ReadPosition(session: chat, messages: 2)))
}

@Test func clearedBotChatShowsUnreadOnTheNextReply() throws {
    let store = try readBeforeTheDrop()
    #expect(try step(store, messages: 2) == nil)
    #expect(try step(store, messages: 4, marker: 2) == .unread)
    store.markSeen(try vera(in: store.bots))
    #expect(store.statuses["vera"] == nil)
    #expect(try step(store, messages: 6, marker: 4) == .unread)
}

@Test func clearSeenEmptyMakesItsFirstReplyUnread() throws {
    let store = try readBeforeTheDrop()
    #expect(try step(store, messages: 0) == nil)
    let empty = try vera(in: store.bots)
    #expect(empty.lastRead == ReadPosition(session: chat, messages: 0))
    #expect(empty.needsMarker(at: ReadPosition(session: chat, messages: 0)))
    #expect(try step(store, messages: 2, marker: 0) == .unread)
}

@Test func inPlaceCompactionMidTurnIsNotUnread() throws {
    let store = try readBeforeTheDrop()
    #expect(try step(store, messages: 5, live: "working") == .working)
    #expect(try step(store, messages: 5) == nil)
    #expect(try step(store, messages: 6, marker: 5) == .unread)
}

@Test func retryOrUndoIsNotUnreadUntilANewReply() throws {
    let store = try readBeforeTheDrop()
    #expect(try step(store, messages: 15) == nil)
    #expect(try step(store, messages: 15, marker: 15) == nil)
    #expect(try step(store, messages: 17, marker: 15) == .unread)
}

@Test func droppedCountWithoutAMarkerIsReadUntilANewReply() throws {
    let store = try readBeforeTheDrop(marker: .some(nil))
    #expect(try vera(in: store.bots).readPosition == nil)
    #expect(try step(store, messages: 2, marker: .some(nil)) == nil)
    #expect(try step(store, messages: 4, marker: .some(nil)) == .unread)
}

@Test func compactionTipIsNotADrop() throws {
    let tip = try vera(in: try roster("cleared-bot-chat", session: "20261017_120000_abcdef"))
    #expect(tip.lastRead == tip.readPosition)
    #expect(!tip.needsMarker(at: ReadPosition(session: chat, messages: 2)))
}
