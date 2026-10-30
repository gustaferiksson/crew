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
    let clock = ContinuousClock()
    let parse = clock.measure { for _ in 0..<5 { _ = parseMarkdownBlocks(from: reply) } } / 5
    let streaming = clock.measure {
        for prefix in prefixes { _ = markdownBlocks(from: prefix) }
    }
    #expect(streaming < parse * 40, "\(prefixes.count) tokens took \(streaming), one parse of the whole reply \(parse)")
}
