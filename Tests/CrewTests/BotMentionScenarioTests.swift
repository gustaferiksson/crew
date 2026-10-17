import Foundation
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/bot-mention")

private func recorded<Value: Decodable>(_ name: String, as type: Value.Type, keys: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = keys
    return try decoder.decode(type, from: Data(contentsOf: scenario.appending(path: "\(name).json")))
}

private func history(_ name: String) throws -> [HistoryRow] {
    try recorded(name, as: [HistoryRow].self, keys: .convertFromSnakeCase)
}

private func chatRows(_ transcript: Transcript) -> [String] {
    transcript.visible.turns.flatMap { turn in
        [
            turn.notice.map { "notice: \($0)" },
            turn.prompt.flatMap { $0.attachments.isEmpty ? nil : "attachments: \($0.attachments.count)" },
            turn.prompt.flatMap { $0.text.isEmpty ? nil : "bubble: \($0.text)" },
            turn.work.isEmpty && turn.status != .streaming ? nil : "work log: \(turn.work.count)",
            turn.reply.isEmpty ? nil : "reply: \(turn.reply)",
            turn.status == .error ? "error: \(turn.failure ?? "")" : nil,
            turn.status == .interrupted ? "stopped" : nil,
        ].compactMap(\.self)
    }
}

private func replayedStore() throws -> BotStore {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.before", as: Roster.self).profiles)
    store.apply(roster: try recorded("profiles.during", as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.during", as: ActiveList.self).sessions)
    store.apply(roster: try recorded("profiles.after", as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.after", as: ActiveList.self).sessions)
    store.showPreview(of: "crew-test", from: try history("crew-test.preview"))
    store.showPreview(of: "crew-test-peer", from: try history("crew-test-peer.preview"))
    return store
}

@Test func senderChatShowsThePromptAndOneRelay() throws {
    #expect(chatRows(Transcript(history: try history("crew-test.history"))) == [
        "bubble: @crew-test-peer hi",
        "work log: 1",
        "reply: 👋",
        "reply: @crew-test-peer: “Hello! Great to hear from you.”",
    ])
}

@Test func mentionedBotChatShowsOneCollapsedExchange() throws {
    let transcript = Transcript(history: try history("crew-test-peer.history"))
    #expect(transcript.turns.count == 2)
    #expect(chatRows(transcript) == ["work log: 4"])
    #expect(transcript.visible.turns.first?.agentMessage?.sender == "Crew Test")
}

@Test func botRowsShowTheLastVisibleTurn() throws {
    let store = try replayedStore()
    #expect(store.previews["crew-test"]?.text == "@crew-test-peer: “Hello! Great to hear from you.”")
    #expect(store.previews["crew-test-peer"]?.text == "Message from Crew Test")
    #expect(store.bots.first { $0.name == "crew-test-peer" }?.description == "Crew scenario peer")
    let open = ChatSessions(fixture: try ["crew-test", "crew-test-peer"].reduce(into: [:]) { sessions, name in
        guard let bot = store.bots.first(where: { $0.name == name }) else { return }
        sessions[name] = ChatSession(fixture: bot, transcript: Transcript(history: try history("\(name).history")), todos: [])
    })
    #expect(open.sessions["crew-test"]?.transcript.preview == store.previews["crew-test"])
    #expect(open.sessions["crew-test-peer"]?.transcript.preview == store.previews["crew-test-peer"])
}

@Test func exchangeShowsWorkingThenUnread() throws {
    let store = BotStore(fixture: [], statuses: [:])
    let chats = ChatSessions()
    store.apply(roster: try recorded("profiles.before", as: Roster.self).profiles)
    store.apply(live: [])
    #expect(chats.status(of: "crew-test", in: store) == .idle)
    store.apply(roster: try recorded("profiles.during", as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.during", as: ActiveList.self).sessions)
    #expect(chats.status(of: "crew-test", in: store) == .working)
    #expect(chats.status(of: "crew-test-peer", in: store) == .idle)
    let replayed = try replayedStore()
    #expect(chats.status(of: "crew-test", in: replayed) == .unread)
    #expect(chats.status(of: "crew-test-peer", in: replayed) == .unread)
}

@Test func senderTimeIsThePromptHeartbeat() throws {
    let before = try recorded("profiles.before", as: Roster.self).profiles
    let store = try replayedStore()
    let sentAt = try history("crew-test.history").first { $0.role == "user" }?.timestamp
    let hiddenAt = try history("crew-test.history").first { AgentMessage($0.content ?? "") != nil }?.timestamp
    let lastActive = { (bots: [Bot], name: String) in bots.first { $0.name == name }?.canonicalSession?.lastActive?.timeIntervalSince1970 }
    #expect(try #require(lastActive(store.bots, "crew-test")) > #require(lastActive(before, "crew-test")))
    #expect(try #require(lastActive(store.bots, "crew-test")) > #require(sentAt))
    #expect(try #require(lastActive(store.bots, "crew-test")) < #require(hiddenAt))
    #expect(lastActive(before, "crew-test-peer") == nil)
    #expect(lastActive(store.bots, "crew-test-peer") != nil)
}

@Test func agentBuildIsNotWorking() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.during", as: Roster.self).profiles)
    let during = try String(contentsOf: scenario.appending(path: "active_list.during.json"), encoding: .utf8)
    let starting = during.replacingOccurrences(of: #""status" : "working""#, with: #""status" : "starting""#)
    #expect(starting != during)
    store.apply(live: try JSONDecoder().decode(ActiveList.self, from: Data(starting.utf8)).sessions)
    #expect(store.statuses["crew-test"] != .working)
}
