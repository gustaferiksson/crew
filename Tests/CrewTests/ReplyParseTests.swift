import Foundation
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

@Test func redrawingLongRepliesReusesTheirParse() throws {
    let replies = try longReplies()
    #expect(replies.count == 6)
    #expect(replies.allSatisfy { !markdownBlocks(from: $0).isEmpty })
    let cache = ParseCache<Int>(costLimit: 4 * 1024 * 1024)
    var parses = 0
    for _ in 0..<20 {
        for reply in replies {
            _ = cache.value(for: reply) { _ in
                parses += 1
                return parses
            }
        }
    }
    #expect(parses == replies.count, "20 redraws of \(replies.count) replies parsed \(parses) times")
}

private let edgeCases = [
    "1. First\n\n2. Second, loose\n\n   Continued under it.\n\nAfter the list.",
    "Intro\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n\nOutro",
    "~~~\n```\n\nstill code\n~~~\n\nText",
    "> Quoted\n\n> Second quote\n\n- item\n\n- another\n\n---\n\n# Heading\n\nBody",
    "See [the docs][docs].\n\n[docs]: https://example.com",
    "| a | b |\n| - | - |\n| 1 | 2 |\n\nAfter the table.",
]

private func longReplies() throws -> [String] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.long-replies.history.json")
    let rows = try decoder.decode(HistoryFile.self, from: Data(contentsOf: file)).messages
    return Transcript(history: rows).turns.map(\.reply).filter { !$0.isEmpty }.map(a2uiFenced)
}

@Test func sectionedRepliesRenderLikeOneParse() throws {
    let inline = { (blocks: [MarkdownBlock]) in
        blocks.map { block in
            var content = block.content
            content.presentationIntent = nil
            return content
        }
    }
    for source in try longReplies() + edgeCases {
        let sectioned = markdownBlocks(from: source)
        let whole = parseMarkdownBlocks(from: source)
        #expect(sectioned.map(\.id) == whole.map(\.id))
        #expect(sectioned.map(\.kind) == whole.map(\.kind))
        #expect(inline(sectioned) == inline(whole))
    }
}

@Test func streamingALongReplyReparsesOnlyItsLastSection() throws {
    let reply = try #require(try longReplies().max { $0.count < $1.count })
    let prefixes = stride(from: 30, to: reply.count, by: 30).map { String(reply.prefix($0)) + " streaming" }
    var parsed = Set<String>()
    var parsedCharacters = 0
    for prefix in prefixes {
        for section in markdownSections(of: prefix) where parsed.insert(section).inserted {
            parsedCharacters += section.count
        }
    }
    #expect(parsedCharacters < reply.count * 40, "\(prefixes.count) tokens parsed \(parsedCharacters) characters of a \(reply.count) character reply")
}
