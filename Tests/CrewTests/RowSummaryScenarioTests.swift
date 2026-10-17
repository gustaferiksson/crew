import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private func recorded<Value: Decodable>(_ name: String, in scenario: String, as type: Value.Type, keys: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = keys
    return try decoder.decode(type, from: Data(contentsOf: fixtures.appending(path: "scenarios/\(scenario)/\(name).json")))
}

private func history(_ name: String, in scenario: String) throws -> [HistoryRow] {
    try recorded(name, in: scenario, as: [HistoryRow].self, keys: .convertFromSnakeCase)
}

private func coldOpenChat(_ store: BotStore) throws -> (ChatSessions, ChatSession) {
    let rows = try history("crew-test-peer.history", in: "cold-open")
    let hi = try #require(rows.first { $0.content == "Hi" })
    var transcript = Transcript(history: rows.filter { $0.id < hi.id })
    transcript.begin(prompt: "Hi", at: Date(timeIntervalSince1970: hi.timestamp))
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    let session = ChatSession(fixture: bot, transcript: transcript, todos: [])
    return (ChatSessions(fixture: ["crew-test-peer": session]), session)
}

@Test func coldOpenedChatShowsWorkingWhileTheServerSaysStarting() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.before", in: "cold-open", as: Roster.self).profiles)
    store.apply(live: [])
    store.apply(roster: try recorded("profiles.starting", in: "cold-open", as: Roster.self).profiles)
    let starting = try recorded("active_list.starting", in: "cold-open", as: ActiveList.self).sessions
    store.apply(live: starting)
    #expect(starting.map(\.status) == ["starting"])
    #expect(store.statuses["crew-test-peer"] == .unread)

    let (chats, _) = try coldOpenChat(store)
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    let summary = chats.summary(of: bot, in: store)
    #expect(summary.status == .working)
    #expect(summary.preview == "Hi")
    let hi = try #require(try history("crew-test-peer.history", in: "cold-open").first { $0.content == "Hi" })
    #expect(summary.time == Date(timeIntervalSince1970: hi.timestamp))
    #expect(summary.time != bot.canonicalSession?.lastActive)
}

@Test func rowTimeIsTheReplyNotTheServersLastActive() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.before", in: "cold-open", as: Roster.self).profiles)
    store.apply(roster: try recorded("profiles.after", in: "cold-open", as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.after", in: "cold-open", as: ActiveList.self).sessions)
    let rows = try history("crew-test-peer.history", in: "cold-open")
    store.showPreview(of: "crew-test-peer", from: rows)
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    let reply = try #require(rows.last)
    let expected = BotSummary(status: .unread, preview: "Hi! What can I help you with?", time: Date(timeIntervalSince1970: reply.timestamp))

    #expect(ChatSessions().summary(of: bot, in: store) == expected)
    #expect(bot.canonicalSession?.lastActive != expected.time)
    let open = ChatSessions(fixture: ["crew-test-peer": ChatSession(fixture: bot, transcript: Transcript(history: rows), todos: [])])
    #expect(open.summary(of: bot, in: store) == expected)
}

@Test func rowTimeMovesWhenALiveReplyLands() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.before", in: "cold-open", as: Roster.self).profiles)
    store.apply(roster: try recorded("profiles.working", in: "cold-open", as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.working", in: "cold-open", as: ActiveList.self).sessions)
    let (chats, session) = try coldOpenChat(store)
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    let sent = try #require(chats.summary(of: bot, in: store).time)
    #expect(chats.summary(of: bot, in: store).status == .working)

    let replayed = Date.now
    let lines = try String(contentsOf: fixtures.appending(path: "chat.tool-turn.v0.21.7.jsonl"), encoding: .utf8).split(separator: "\n")
    for line in lines { session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(line.utf8))) }
    store.apply(roster: try recorded("profiles.after", in: "cold-open", as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.after", in: "cold-open", as: ActiveList.self).sessions)

    let summary = chats.summary(of: bot, in: store)
    #expect(session.isRunning == false)
    #expect(summary.status == .unread)
    #expect(summary.preview == session.transcript.turns.last?.reply.split(whereSeparator: \.isWhitespace).joined(separator: " "))
    #expect(try #require(summary.time) >= replayed)
    #expect(try #require(summary.time) > sent)
}

@Test func clearedBotChatIsTheSameSessionWithOnlyItsNewRows() throws {
    let before = try recorded("profiles.after", in: "untitled-bot-chat", as: Roster.self).profiles
    let after = try recorded("profiles.after", in: "cleared-bot-chat", as: Roster.self).profiles
    let earlier = try #require(before.first { $0.name == "vera" }?.canonicalSession)
    let vera = try #require(after.first { $0.name == "vera" })
    let session = try #require(vera.canonicalSession)
    #expect(session.id == earlier.id)
    #expect(session.messageCount == 2)
    #expect(try recorded("active_list.after", in: "cleared-bot-chat", as: ActiveList.self).sessions.map(\.sessionKey) == [session.id])

    let rows = try history("vera.history", in: "cleared-bot-chat")
    let shown = Transcript(history: rows).visible.turns
    #expect(shown.map { $0.prompt?.text } == ["Hi"])
    #expect(shown.map(\.reply) == ["Hi Sam! What can I help you with?"])

    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: after)
    store.apply(live: try recorded("active_list.after", in: "cleared-bot-chat", as: ActiveList.self).sessions)
    store.showPreview(of: "vera", from: rows)
    let reply = try #require(rows.last)
    #expect(ChatSessions().summary(of: vera, in: store) == BotSummary(status: .idle, preview: "Hi Sam! What can I help you with?", time: Date(timeIntervalSince1970: reply.timestamp)))
}
