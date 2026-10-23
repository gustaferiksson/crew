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
    let firstPass = ContinuousClock().measure {
        for reply in replies { _ = markdownBlocks(from: a2uiFenced(reply)) }
    }
    var blocks = 0
    let redraws = ContinuousClock().measure {
        for _ in 0..<100 {
            for reply in replies { blocks += markdownBlocks(from: a2uiFenced(reply)).count }
        }
    }
    print("first pass \(firstPass), 100 redraws \(redraws)")
    #expect(blocks > 0)
    #expect(redraws < .milliseconds(100))
}
