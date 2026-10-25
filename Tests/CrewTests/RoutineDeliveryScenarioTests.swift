import Foundation
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/routine-delivery")
private let reply = "Two items need attention, according to the morning brief: - Anna wants to move Friday’s lunch to 12:30. Does that work for you? - Telia’s invoice for 412 kr is due October 31. No reply, calendar change, or payment has been made."

private func recorded<Value: Decodable>(_ name: String, as type: Value.Type, keys: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = keys
    return try decoder.decode(type, from: Data(contentsOf: scenario.appending(path: "\(name).json")))
}

private func history(_ name: String) throws -> [HistoryRow] {
    try recorded(name, as: [HistoryRow].self, keys: .convertFromSnakeCase)
}

private func summary(roster: String, window: String?) throws -> BotSummary {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded(roster, as: Roster.self).profiles)
    if let window { store.showPreview(of: "crew-test-peer", from: try history(window)) }
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    return ChatSessions().summary(of: bot, in: store)
}

@Test func routineHandOffIsANoticeAboveTheBotsReply() throws {
    let turns = Transcript(history: try history("crew-test-peer.history")).visible.turns
    #expect(turns.count == 1)
    #expect(turns[0].notice == "Routine: Morning brief")
    #expect(turns[0].prompt == nil)
    #expect(turns[0].agentMessage == nil)
    #expect(turns[0].work.count == 1)
    #expect(turns[0].reply.hasPrefix("Two items need attention"))
}

@Test func liveRoutineHandOffIsANotice() {
    var transcript = Transcript()
    transcript.begin(remote: "[Cronjob \"[bot:atlas] Say \"hi\" daily\" output — scheduled job, not the user. Review it, act on anything that needs action, and summarize for the chat.]\n\nHi.", displayKind: nil, at: .now)
    #expect(transcript.turns.last?.notice == "Routine: Say \"hi\" daily")
    #expect(transcript.turns.last?.prompt == nil)
}

@Test func botRowReadsTheRoutineWhileTheBotWorks() throws {
    #expect(try summary(roster: "profiles.during", window: "crew-test-peer.preview.during").preview == "Routine: Morning brief")
}

@Test func botRowMapsTheServersRawBrief() throws {
    #expect(try summary(roster: "profiles.during", window: nil).preview == "Routine: Morning brief")
}

@Test func botRowReadsTheReplyOnceItLands() throws {
    let row = try summary(roster: "profiles.after", window: "crew-test-peer.preview")
    #expect(row.preview == reply)
    #expect(row.time == Date(timeIntervalSince1970: 1792933065.298869))
}
