import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let steerText = "Sounds worth a try, go ahead and order it :)"
private let reply = "Going ahead with shop.example. Add it in Crew and I'll continue the purchase."

private struct HistoryPage: Decodable {
    let messages: [HistoryRow]
}

private func rows() throws -> [HistoryRow] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(HistoryPage.self, from: Data(contentsOf: fixtures.appending(path: "chat.steer-shop.history.json"))).messages
}

private func shown(_ transcript: Transcript) -> [String] {
    transcript.visible.turns.map { turn in
        let tools = turn.work.compactMap { item -> String? in if case .tool(let call) = item.kind { call.name } else { nil } }
        let bubble = turn.prompt.map { "\(turn.isSteer ? "steer" : "bubble") \($0.text)" } ?? "no bubble"
        return "\(bubble) | tools \(tools.count) \(tools.last ?? "-") | reply \(turn.reply)"
    }
}

@Test func aMidTurnSteerShowsTheUsersWordsBetweenTheTwoRuns() throws {
    #expect(shown(Transcript(history: try rows())) == [
        "no bubble | tools 0 - | reply The lowest verified total is at shop.example, shipping included.",
        "bubble Can you ask me to add the shop? | tools 9 browser_exec | reply ",
        "steer \(steerText) | tools 1 tool_call | reply \(reply)",
    ])
}

@Test func noTurnInTheSteerHistoryDrawsAnEmptyBubble() throws {
    let turns = Transcript(history: try rows()).visible.turns
    #expect(turns.allSatisfy { $0.prompt.map { !$0.text.isEmpty || !$0.attachments.isEmpty } ?? true })
    #expect(turns.allSatisfy { !($0.prompt?.text.contains("OUT-OF-BAND") ?? false) })
}

@Test func aSteerRowWithoutDisplayContentStillShowsOnlyTheWords() throws {
    let bare = try rows().map { row in
        HistoryRow(id: row.id, role: row.role, content: row.content, toolCallId: row.toolCallId, toolCalls: row.toolCalls, timestamp: row.timestamp, reasoning: row.reasoning, reasoningContent: row.reasoningContent, displayKind: row.displayKind, displayContent: nil, displayCommentary: row.displayCommentary, displayReasoning: row.displayReasoning)
    }
    #expect(shown(Transcript(history: bare)).last == "steer \(steerText) | tools 1 tool_call | reply \(reply)")
    let store = BotStore(fixture: [], statuses: [:])
    store.showPreview(of: "crew-test", from: bare.filter { $0.id == 151 })
    #expect(store.previews["crew-test"]?.text == steerText)
}

@Test func theBotRowPreviewIsTheReplyAfterTheSteer() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.showPreview(of: "crew-test", from: try rows())
    #expect(store.previews["crew-test"]?.text == reply)
    store.showPreview(of: "crew-test", from: try rows().filter { $0.id >= 151 })
    #expect(store.previews["crew-test"]?.text == reply)
    store.showPreview(of: "crew-test", from: try rows().filter { $0.id == 151 })
    #expect(store.previews["crew-test"]?.text == steerText)
}

@Test func aLiveTakenSteerKeepsItsTextThroughTheHistorySync() throws {
    let history = try rows()
    var live = Transcript(history: history.filter { $0.id < 151 })
    live.turns[live.turns.count - 1].status = .streaming
    live.wait(Prompt(text: steerText, sentAt: .now), as: .steer, id: "local-steer")
    live.apply(.toolStart(id: "vault", name: "browser_vault", context: nil, arguments: "{}"))
    live.apply(.toolComplete(id: "vault", duration: 0.1, summary: nil, result: "{}"))
    live.apply(.messageDelta(reply))
    live.apply(.messageComplete(text: reply, status: .complete, error: nil))
    #expect(live.visible.turns.last?.prompt?.text == steerText)
    #expect(live.visible.turns.last?.pending == nil)
    var synced = Transcript(history: history)
    synced.adoptIDs(from: live)
    #expect(synced.turns.last?.id == "local-steer")
    #expect(synced.turns.last?.prompt?.text == steerText)
}

@Test func twoJoinedSteersSyncedUnderTheRowIDKeepTheirText() throws {
    let history = try rows()
    var live = Transcript(history: history.filter { $0.id < 151 })
    live.turns[live.turns.count - 1].status = .streaming
    live.wait(Prompt(text: "Sounds worth a try,", sentAt: .now), as: .steer, id: "first")
    live.wait(Prompt(text: "go ahead and order it :)", sentAt: .now), as: .steer, id: "second")
    live.apply(.toolStart(id: "vault", name: "browser_vault", context: nil, arguments: "{}"))
    live.apply(.toolComplete(id: "vault", duration: 0.1, summary: nil, result: "{}"))
    live.apply(.messageDelta(reply))
    #expect(live.visible.turns.last?.prompt?.text == "Sounds worth a try,\ngo ahead and order it :)")
    var synced = Transcript(history: history)
    synced.adoptIDs(from: live)
    #expect(synced.turns.last?.id == "151")
    #expect(synced.turns.last?.prompt?.text == steerText)
}
