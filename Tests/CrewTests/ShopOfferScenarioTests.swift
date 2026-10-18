import Foundation
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/shop-offer-history")

private func rows(through last: Int = .max) throws -> [HistoryRow] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode([HistoryRow].self, from: Data(contentsOf: scenario.appending(path: "vera.history.json"))).filter { $0.id <= last }
}

private func row(_ json: String) throws -> HistoryRow {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(HistoryRow.self, from: Data(json.utf8))
}

private func calls(_ turn: Turn) -> [ToolCall] {
    turn.work.compactMap { if case .tool(let call) = $0.kind { call } else { nil } }
}

@Test func offerSurvivesTheReloadAfterTheStoppedTurn() throws {
    let transcript = Transcript(history: try rows(through: 134))
    let turn = try #require(transcript.turns.last)
    #expect(turn.prompt?.text.hasPrefix("It's up to you to find where it's cheapest") == true)
    #expect(calls(turn).map(\.name) == ["browser_vault"])
    #expect(calls(turn).map(\.arguments) == [#"{"action":"list"}"#])
    #expect(calls(turn).first?.result?.hasPrefix(#"{"success": true, "items": []"#) == true)
    #expect(calls(turn).first?.status == .success)
    #expect(turn.missingShop == "shop.example.se")
    #expect(turn.paymentReceipts.isEmpty)
}

@Test func storedRowsGiveWhatTheLiveTurnShowed() throws {
    let stored = try rows(through: 134)
    let result = try #require(Transcript(history: stored).turns.last.flatMap { calls($0).first?.result })
    var live = Transcript()
    live.begin(prompt: try #require(stored.first?.content))
    live.apply(.toolStart(id: "call_30c2f1abd29d491188acccd31a878b75", name: "browser_vault", context: nil, arguments: #"{"action":"list"}"#))
    live.apply(.toolComplete(id: "call_30c2f1abd29d491188acccd31a878b75", duration: nil, summary: nil, result: result))
    live.apply(.messageComplete(text: try #require(stored.last?.content), status: .complete, error: nil))
    let reloaded = try #require(Transcript(history: stored).turns.last)
    let shown = try #require(live.turns.last)
    #expect(calls(reloaded).map(\.name) == calls(shown).map(\.name))
    #expect(calls(reloaded).map(\.result) == calls(shown).map(\.result))
    #expect(reloaded.missingShop == shown.missingShop)
    #expect(reloaded.reply == shown.reply)
}

@Test func laterListWithoutMissingShopHidesTheOfferUntilTheBotListsAgain() throws {
    let transcript = Transcript(history: try rows())
    let turns = transcript.turns
    #expect(turns.count == 3)
    #expect(turns[1].prompt?.text == "I think you might be able to ask for a shop add?")
    #expect(turns[1].missingShop == nil)
    #expect(turns[2].isSteer)
    #expect(turns[2].missingShop == "shop.example.se")
}

@Test func botRowPreviewIsTheBotsReply() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.showPreview(of: "vera", from: try rows())
    #expect(store.previews["vera"]?.text.hasPrefix("I'll treat that as your approval for 278 kr.") == true)
}

@Test func addingTheShopEndsTheOfferOnEveryDevice() throws {
    let added = try row(#"{"id": 160, "role": "user", "content": "I added https://shop.example.se to your shops. Continue the purchase.", "display_kind": "hidden", "timestamp": 1792324700}"#)
    let transcript = Transcript(history: try rows() + [added])
    #expect(transcript.turns.last?.notice == "Added shop.example.se to Shops")
    #expect(transcript.turns.last?.missingShop == nil)
}
