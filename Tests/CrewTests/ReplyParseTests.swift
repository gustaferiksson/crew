import Foundation
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

@Test func redrawingLongRepliesReusesTheirParse() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.long-replies.history.json")
    let rows = try decoder.decode(HistoryFile.self, from: Data(contentsOf: file)).messages
    let replies = Transcript(history: rows).turns.map(\.reply).filter { !$0.isEmpty }
    #expect(replies.count == 6)
    #expect(replies.allSatisfy { !markdownBlocks(from: a2uiFenced($0)).isEmpty })
    let clock = ContinuousClock()
    let parsing = clock.measure {
        for _ in 0..<20 { for reply in replies { _ = parseMarkdownBlocks(from: a2uiFenced(reply)) } }
    }
    let redrawing = clock.measure {
        for _ in 0..<20 { for reply in replies { _ = markdownBlocks(from: a2uiFenced(reply)) } }
    }
    #expect(redrawing < parsing / 4, "20 redraws took \(redrawing), 20 parses \(parsing)")
    let building = clock.measure {
        for _ in 0..<20 { for reply in replies { _ = buildReplySegments(from: a2uiFenced(reply)) } }
    }
    let macRedrawing = clock.measure {
        for _ in 0..<20 { for reply in replies { _ = replySegments(from: a2uiFenced(reply)) } }
    }
    #expect(macRedrawing < building / 4, "20 Mac redraws took \(macRedrawing), 20 builds \(building)")
}
