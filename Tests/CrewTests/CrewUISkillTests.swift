import A2UICore
import Foundation
import Testing

private func skillBlocks() throws -> [String] {
    let skill = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/Profile/crew-ui.SKILL.md"), encoding: .utf8)
    return markdownBlocks(from: skill).filter { $0.kind == .code(language: "a2ui") }.map { String($0.content.characters) }
}

@MainActor @Test func everySkillExampleBuildsACardWithAHeader() throws {
    let blocks = try skillBlocks()
    try #require(blocks.count == 5)

    for block in blocks {
        let model = try surface(block)
        #expect(model.rootNode?.type == "Card")
        #expect(nodes(model.rootNode).contains { $0.type == "Header" }, "\(block.prefix(120))")
    }
}

@MainActor @Test func theSkillShoppingListTicksOffEveryItemUnderItsSection() throws {
    let block = try #require(try skillBlocks().first { $0.contains("taco-shopping-list") })
    let model = try surface(block)
    let rows = nodes(model.rootNode).filter { $0.type == "CheckBox" }

    #expect(rows.map { $0.string(for: "label") ?? "" } == [
        "2 avocados", "1 red onion", "3 tomatoes", "1 lime", "500 g minced beef", "2 dl crème fraîche", "150 g grated cheese", "8 tortillas", "1 jar salsa",
    ])
    #expect(nodes(model.rootNode).filter { $0.type == "Text" && $0.string(for: "variant") == "h4" }.map { $0.string(for: "text") } == ["Produce", "Dairy and meat", "Pantry"])
}

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

@MainActor @Test func theRealBotsUnaskedShoppingListComesBackUnderTheSameIdWhenItChanges() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.a2ui-shopping.history.json")
    let transcript = Transcript(history: try decoder.decode(HistoryFile.self, from: Data(contentsOf: file)).messages)
    let store = SurfaceStore()
    store.sync(transcript)
    let blocks = transcript.turns.compactMap { turn in
        markdownBlocks(from: a2uiFenced(turn.reply)).first { $0.kind == .code(language: "a2ui") }.map { String($0.content.characters).trimmingCharacters(in: .newlines) }
    }
    try #require(blocks.count == 2)

    #expect(store.blocks[blocks[1]] == .surfaces(created: ["taco-shopping-list"], revised: ["taco-shopping-list"], updated: []), "the follow-up re-sends the whole card")
    let model = try #require(store.processor.surfaceGroupModel["taco-shopping-list"])
    #expect(nodes(model.rootNode).filter { $0.type == "CheckBox" }.map { $0.string(for: "label") ?? "" } == [
        "1 small lettuce", "3 tomatoes (reserve 1 for guacamole)", "2 ripe avocados", "1 lime", "1 small red onion (use half for guacamole)",
        "1 bulb garlic (use 1 clove for guacamole)", "1 small bunch fresh coriander (optional)", "500 g minced beef", "200 ml sour cream",
        "12 small tortillas or taco shells", "1 packet taco seasoning (for 500 g meat)", "1 jar salsa (about 250 g)",
    ])
}
