import Foundation
import Testing

private let scenarios = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios")

private func recorded<Value: Decodable>(_ name: String, in scenario: String, as type: Value.Type, keys: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = keys
    return try decoder.decode(type, from: Data(contentsOf: scenarios.appending(path: "\(scenario)/\(name).json")))
}

private struct Row: Equatable {
    let status: BotStatus
    let time: Date?
    let preview: String
}

private func row(_ name: String, in store: BotStore) -> Row? {
    guard let bot = store.bots.first(where: { $0.name == name }) else { return nil }
    let preview = store.previews[name] ?? bot.canonicalSession?.preview ?? ""
    let status = ChatSessions().status(of: name, in: store)
    let time = [.idle, .unread].contains(status) ? bot.canonicalSession?.lastActive : nil
    return Row(status: status, time: time, preview: preview.isEmpty ? bot.description ?? "" : preview)
}

@Test func newBotChatShowsNoTimeThenWorkingThenTheReply() throws {
    let scenario = "new-bot-chat"
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.before", in: scenario, as: Roster.self).profiles)
    store.apply(live: [])
    #expect(row("crew-test-peer", in: store) == Row(status: .idle, time: nil, preview: "Crew scenario bot"))

    store.apply(roster: try recorded("profiles.opened", in: scenario, as: Roster.self).profiles)
    #expect(row("crew-test-peer", in: store) == Row(status: .idle, time: Date(timeIntervalSince1970: 1792229985.4728801), preview: "Crew scenario bot"))

    store.apply(roster: try recorded("profiles.during", in: scenario, as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.during", in: scenario, as: ActiveList.self).sessions)
    #expect(row("crew-test-peer", in: store) == Row(status: .working, time: nil, preview: "Use your terminal tool to run: sleep 6 && echo fresh-ok. Then reply with just th..."))

    store.apply(roster: try recorded("profiles.after", in: scenario, as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.after", in: scenario, as: ActiveList.self).sessions)
    store.showPreview(of: "crew-test-peer", from: try recorded("crew-test-peer.preview", in: scenario, as: [HistoryRow].self, keys: .convertFromSnakeCase))
    #expect(row("crew-test-peer", in: store) == Row(status: .unread, time: Date(timeIntervalSince1970: 1792230042.9846604), preview: "fresh-ok"))
}

@Test func botChatThatLostItsTitleShowsNoStatusOrTime() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.during", in: "untitled-bot-chat", as: Roster.self).profiles)
    let live = try recorded("active_list.during", in: "untitled-bot-chat", as: ActiveList.self).sessions
    store.apply(live: live)
    #expect(live.map(\.status) == ["working"])
    #expect(store.bots.first { $0.name == "default" }?.title == "Marlow")
    #expect(row("default", in: store) == Row(status: .idle, time: nil, preview: ""))
}

@Test func veraShowsHerLastReplyNotHerDescription() throws {
    let scenario = "untitled-bot-chat"
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.after", in: scenario, as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.after", in: scenario, as: ActiveList.self).sessions)
    let rows = try recorded("vera.preview", in: scenario, as: [HistoryRow].self, keys: .convertFromSnakeCase)
    let description = "Gustaf's personal assistant: shopping research, occasions, restaurants, reminders, personal email and calendars."

    store.showPreview(of: "vera", from: rows.filter { $0.id <= 6 })
    #expect(row("vera", in: store)?.preview == "I’m Vera, your personal assistant for gifts, shopping research, occasions, restaurants and personal admin.")

    store.showPreview(of: "vera", from: rows)
    #expect(row("vera", in: store) == Row(status: .idle, time: Date(timeIntervalSince1970: 1792228402.3980901), preview: try #require(rows.last?.content)))
    #expect(store.bots.first { $0.name == "vera" }?.description == description)
}
