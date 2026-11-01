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

private func longRecipeBlock() throws -> String {
    let lines = try recordedRecipeBlock().components(separatedBy: "\n")
    let body = lines.dropFirst(2).dropLast().joined(separator: "\n")
    return (lines.prefix(2) + [Array(repeating: body, count: 8).joined(separator: ",\n"), "]"]).joined(separator: "\n")
}

private func refreshedPrefixes(of block: String) -> [String] {
    var step = -1
    return (1...block.utf8.count).compactMap { length in
        guard previewStep(forLength: length) != step else { return nil }
        step = previewStep(forLength: length)
        return String(decoding: block.utf8.prefix(length), as: UTF8.self)
    }
}

@MainActor @Test func aStreamingCardShowsItsHeaderLongBeforeTheFenceCloses() throws {
    let block = try recordedRecipeBlock()
    let store = SurfaceStore()
    let shownAt = try #require(refreshedPrefixes(of: block).first { CardSummary(store.preview($0)?.rootNode).title != nil }, "no preview before the fence closed").utf8.count
    #expect(shownAt < block.utf8.count / 4, "header shown after \(shownAt) of \(block.utf8.count) bytes")
    let final = try #require(store.preview(String(block.dropLast())))
    #expect(store.preview(String(block.dropLast())) === final, "an unchanged prefix gives back the same preview, so a recycled row keeps its card")
}

@MainActor @Test(arguments: [false, true]) func previewingAWholeStreamCostsAboutThirtyFiveFullPreviews(long: Bool) throws {
    let block = long ? try longRecipeBlock() : try recordedRecipeBlock()
    let clock = ContinuousClock()
    let full = clock.measure { for _ in 0..<3 { _ = SurfaceStore().preview(block) } } / 3
    let store = SurfaceStore()
    let prefixes = refreshedPrefixes(of: block)
    let elapsed = clock.measure {
        for prefix in prefixes { _ = store.preview(prefix) }
    }
    let perToken = elapsed / (Double(block.utf8.count) / 3.8)
    #expect(elapsed < full * 60, "\(block.utf8.count) bytes: \(prefixes.count) previews took \(elapsed), one full preview \(full), \(perToken) per token")
}
