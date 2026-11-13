import Foundation
import SwiftUI
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private let recipe = "kottbullar-for-four"
private let vegan = "vegan-kottbullar-for-six"

private func recordedRows() throws -> [HistoryRow] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.a2ui-update.history.json")
    return try decoder.decode(HistoryFile.self, from: Data(contentsOf: file)).messages
}

private func cardBlocks(_ transcript: Transcript) -> [String] {
    transcript.turns.compactMap { turn in
        markdownBlocks(from: a2uiFenced(turn.reply))
            .first { $0.kind == .code(language: "a2ui") }
            .map { String($0.content.characters).trimmingCharacters(in: .newlines) }
    }
}

@MainActor @Test func aRefinedCardMovesDownAndAnUpdateOnlyReplyPointsAtIt() throws {
    let transcript = Transcript(history: try recordedRows())
    let store = SurfaceStore()
    store.sync(transcript)
    let blocks = cardBlocks(transcript)
    try #require(blocks.count == 4)

    #expect(store.blocks[blocks[0]] == .surfaces(created: [recipe], revised: [], updated: []))
    #expect(store.owners[recipe] == blocks[1], "the first turn draws the 'updated below' line, not the card")
    #expect(store.blocks[blocks[1]] == .surfaces(created: [recipe], revised: [recipe], updated: []), "the refined card carries the Updated caption")
    #expect(store.blocks[blocks[2]] == .surfaces(created: [], revised: [], updated: [recipe]), "the tick-off reply shows 'Updated <title>'")
    #expect(store.present.contains(recipe))
    #expect(store.blocks[blocks[3]] == .surfaces(created: [vegan], revised: [], updated: []), "a vegan version is a second card, no caption")
    #expect(store.owners[vegan] == blocks[3])

    let title = CardSummary(store.processor.surfaceGroupModel[recipe]?.rootNode).title
    #expect(title?.localizedCaseInsensitiveContains("köttbullar") == true, "the lines name the card: \(title ?? "nil")")
    #expect(store.newest?.surface == vegan)
}

@MainActor @Test func theRefinedCardPinsAgainAfterTheOriginalWasUnpinned() throws {
    let rows = try recordedRows()
    let prompts = rows.indices.filter { rows[$0].role == "user" }
    let store = SurfaceStore()
    let pins = ChatPins(fileURL: URL.temporaryDirectory.appending(path: "crew-pins-\(UUID().uuidString)/pins.json"))

    store.sync(Transcript(history: Array(rows[..<prompts[1]])))
    let first = try #require(store.newest)
    pins.arrived(ChatPins.Card(surface: first.surface, source: first.source, finishedAt: .now + 60), in: "chef")
    #expect(pins.pinned(in: "chef") == recipe)
    pins.pin(nil, in: "chef")

    let refinedTranscript = Transcript(history: Array(rows[..<prompts[2]]))
    store.sync(refinedTranscript)
    let refined = try #require(store.newest)
    #expect(refined.surface == recipe)
    #expect(refined.source == cardBlocks(refinedTranscript)[1])
    pins.arrived(ChatPins.Card(surface: refined.surface, source: refined.source, finishedAt: .now + 120), in: "chef")
    #expect(pins.pinned(in: "chef") == recipe, "a refinement is a new block, so it pins as the newest card")

    store.sync(Transcript(history: Array(rows[..<prompts[3]])))
    #expect(store.newest == refined, "an update-only reply is not a new card")
}

@MainActor @Test func anUpdateForACardThatIsGoneSaysSoInsteadOfFailing() throws {
    let rows = try recordedRows()
    let thirdPrompt = try #require(rows.indices.filter { rows[$0].role == "user" }.dropFirst(2).first)
    let transcript = Transcript(history: Array(rows[thirdPrompt...]))
    let store = SurfaceStore()
    store.sync(transcript)
    let blocks = cardBlocks(transcript)
    #expect(store.blocks[blocks[0]] == .lost, "never the 'Couldn't display this card' chip")
}

@MainActor @Test func afterStartNewChatTheOldCardIsNotPresentSoTheUpdateLineSaysItIsGone() throws {
    let rows = try recordedRows()
    let store = SurfaceStore()
    store.sync(Transcript(history: rows))
    let thirdPrompt = try #require(rows.indices.filter { rows[$0].role == "user" }.dropFirst(2).first)
    store.sync(Transcript(history: Array(rows[thirdPrompt...])))
    #expect(store.processor.surfaceGroupModel[recipe] != nil, "the processor outlives the transcript")
    #expect(!store.present.contains(recipe))
    #expect(store.present.contains(vegan))
}

@MainActor @Test func updatedBelowLeadsToTheTurnThatNowHoldsTheCard() throws {
    let transcript = Transcript(history: try recordedRows())
    let store = SurfaceStore()
    store.sync(transcript)
    let cardTurns = transcript.turns.filter { $0.reply.contains("```a2ui") }
    try #require(cardTurns.count == 4)

    #expect(store.cardTurns[recipe] == cardTurns[1].id, "the first turn's line points at the 'make it for 6' turn")
    #expect(store.cardTurns[vegan] == cardTurns[3].id)
}

@Test func onlyALiveReplyAnimatesItsCardUpdates() {
    let earlier: [Turn.Status] = [.complete, .complete]
    let streaming = earlier + [.streaming]
    let finished = earlier + [.complete]

    #expect(Transaction.cardUpdate(from: streaming, to: finished, reducingMotion: false).animation == .smooth, "a reply that just finished animates")
    #expect(Transaction.cardUpdate(from: streaming, to: [.complete] + finished, reducingMotion: false).animation == .smooth, "an earlier page landing as the reply finishes still animates it")
    #expect(Transaction.cardUpdate(from: streaming, to: finished, reducingMotion: true).animation == nil, "never under Reduce Motion")
    #expect(Transaction.cardUpdate(from: finished, to: finished, reducingMotion: false).animation == nil, "opening the chat draws the final state")
    #expect(Transaction.cardUpdate(from: [], to: finished, reducingMotion: false).animation == nil, "history arriving after open draws the final state")
    #expect(Transaction.cardUpdate(from: finished, to: [.complete, .complete] + finished, reducingMotion: false).animation == nil, "Load Earlier replays older blocks without animating")
}
