import AppKit
import SwiftUI
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

@MainActor @Observable private final class Stream {
    var source = ""
}

private struct StreamingBlock: View {
    let stream: Stream

    var body: some View {
        SurfaceBlock(source: stream.source)
            .frame(width: 560, alignment: .leading)
    }
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

@MainActor @Test func aStreamingCardKeepsItsRowHeightFromTheFirstBytes() throws {
    let block = try recordedRecipeBlock()
    let store = SurfaceStore()
    store.sync(Transcript(turns: [Turn(id: "t", prompt: nil, reply: "```a2ui\n", status: .streaming, startedAt: .now)]))
    let stream = Stream()
    let host = NSHostingView(rootView: StreamingBlock(stream: stream).environment(\.surfaces, store).environment(ChatPins(fileURL: nil)))
    let window = OffscreenWindow(size: NSSize(width: 600, height: 400), styleMask: [.borderless])
    window.isRestorable = false
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }

    var heights: [Int: CGFloat] = [:]
    var step = -1
    for length in 30...block.utf8.count where previewStep(forLength: length) != step {
        step = previewStep(forLength: length)
        stream.source = String(decoding: block.utf8.prefix(length), as: UTF8.self)
        settle(0.05)
        heights[length] = host.fittingSize.height.rounded()
    }

    store.sync(Transcript(turns: [Turn(id: "t", prompt: nil, reply: "```a2ui\n\(block)\n```", status: .complete, startedAt: .now, finishedAt: .now)]))
    stream.source = block
    settle(0.05)
    let finished = host.fittingSize.height.rounded()

    let summary = heights.sorted { $0.key < $1.key }.map { "\($0.key):\(Int($0.value))" }.joined(separator: " ")
    #expect(Set(heights.values) == [finished], "row heights while streaming: \(summary), finished: \(Int(finished))")
    #expect(finished > 0)
}

