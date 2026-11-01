import Foundation
import OrderedJSON
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private func recordedRecipeBlock() throws -> String {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.a2ui-update.history.json")
    let rows = try decoder.decode(HistoryFile.self, from: Data(contentsOf: file)).messages
    let reply = try #require(Transcript(history: rows).turns.first?.reply)
    let block = markdownBlocks(from: a2uiFenced(reply)).first { $0.kind == .code(language: "a2ui") }
    return try #require(block.map { String($0.content.characters).trimmingCharacters(in: .newlines) })
}

private func streamedPrefixes(of block: String, every stride: Int) -> [String] {
    Swift.stride(from: stride, to: block.utf8.count, by: stride).map { String(decoding: block.utf8.prefix($0), as: UTF8.self) }
}

@Test func everyHealedPrefixOfAStreamingCardIsValidJSON() throws {
    let block = try recordedRecipeBlock()
    let healed = streamedPrefixes(of: block, every: 1).compactMap(healedA2UIPrefix)
    #expect(healed.count > block.utf8.count / 2)
    for text in healed {
        #expect((try? JSONDecoder().decode(OrderedJSON.JSONValue.self, from: Data(text.utf8))) != nil, "\(text.suffix(80))")
    }
    #expect(healedA2UIPrefix(#"[{"a":"}\"{"#) == nil)
    #expect(healedA2UIPrefix(#"[{"a":1},{"b":[{"c":"x"},{"d":"#) == #"[{"a":1},{"b":[{"c":"x"}]}]"#)
}

@MainActor @Test func aStreamingCardShowsItsHeaderLongBeforeTheFenceCloses() throws {
    let block = try recordedRecipeBlock()
    let store = SurfaceStore()
    let header = streamedPrefixes(of: block, every: 64).firstIndex { prefix in
        CardSummary(store.preview(prefix)?.rootNode).title != nil
    }
    let shownAt = try #require(header, "no preview before the fence closed").advanced(by: 1) * 64
    #expect(shownAt < block.utf8.count / 4, "header shown after \(shownAt) of \(block.utf8.count) bytes")
}

@MainActor @Test func previewingAStreamingCardStaysUnderAMillisecondPerToken() throws {
    let block = try recordedRecipeBlock()
    let store = SurfaceStore()
    let prefixes = streamedPrefixes(of: block, every: 64)
    let tokens = Double(block.utf8.count) / 3.8
    let elapsed = ContinuousClock().measure {
        for prefix in prefixes { _ = store.preview(prefix) }
    }
    let perToken = elapsed / tokens
    #expect(perToken < .milliseconds(1), "\(prefixes.count) previews took \(elapsed), \(perToken) per token over \(Int(tokens)) tokens")
}
