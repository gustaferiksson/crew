import Foundation
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

@MainActor private func summary(of reply: String) throws -> CardSummary {
    let store = SurfaceStore()
    store.sync(Transcript(turns: [Turn(id: "t1", prompt: nil, reply: reply, status: .complete, startedAt: .now, finishedAt: .now)]))
    let id = try #require(store.newest?.surface)
    return CardSummary(store.processor.surfaceGroupModel[id]?.rootNode)
}

@MainActor @Test func theCompactPreviewReadsTheRecordedHeader() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode(HistoryFile.self, from: Data(contentsOf: fixtures.appending(path: "chat.a2ui-update.history.json"))).messages
    let reply = try #require(Transcript(history: rows).turns.first?.reply)
    let card = try summary(of: reply)
    #expect(card.title == "Köttbullar with cream gravy")
    #expect(card.subtitle == "4 servings · About 30 meatballs · 45 minutes")
    #expect(card.symbol == "fork.knife")
    #expect(card.image == nil)
}

@MainActor @Test func aCardWithoutAHeaderPreviewsItsFirstTextLine() throws {
    let card = try summary(of: String(contentsOf: fixtures.appending(path: "chat.a2ui-recipe.v0.21.7.md"), encoding: .utf8))
    #expect(card.title == "Fluffy Pancakes")
    #expect(card.subtitle == nil)
    #expect(card.symbol == "rectangle.on.rectangle")
}

@MainActor @Test func aHeroImageBecomesTheThumbnailOnlyOverHTTPS() throws {
    let card = { (image: String) in
        #"```a2ui"# + "\n" + #"[{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"https://crew.gustaf.dev/catalogs/crew/v1.json"}},{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Card","child":"h"},{"id":"h","component":"Header","title":"Lofoten","image":"\#(image)"}]}}]"# + "\n```"
    }
    #expect(try summary(of: card("https://example.com/lofoten.jpg")).image == URL(string: "https://example.com/lofoten.jpg"))
    #expect(try summary(of: card("http://example.com/lofoten.jpg")).image == nil)
}
