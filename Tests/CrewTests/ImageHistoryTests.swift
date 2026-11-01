import Foundation
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private let imagePath = "/opt/hermes/data/images/upload_hbv1ik2k.png"
private let typed = "Is this dialog a bug?"

private func imageMemoryRows(caption: String = imageOnlyPrompt) throws -> [HistoryRow] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.image-memory.history.json")
    let json = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "\"\(imageOnlyPrompt)\\n", with: "\"\(caption)\\n")
    return try decoder.decode(HistoryFile.self, from: Data(json.utf8)).messages
}

@Test func nativeVisionImageRowShowsOnlyTheImage() throws {
    let transcript = Transcript(history: try imageMemoryRows())
    let prompt = try #require(transcript.turns.first?.prompt)
    #expect(prompt.text == "")
    #expect(prompt.attachments.map(\.kind) == [.image])
    #expect(prompt.attachments.map(\.path) == [imagePath])
    #expect(prompt.attachments.map(\.name) == ["upload_hbv1ik2k.png"])
    #expect(transcript.preview?.text == "I see a chat app with an approval dialog waiting for an answer.")
}

@Test func nativeVisionCaptionKeepsOnlyWhatTheUserTyped() throws {
    let prompt = try #require(Transcript(history: imageMemoryRows(caption: typed)).turns.first?.prompt)
    #expect(prompt.text == typed)
    #expect(prompt.attachments.map(\.path) == [imagePath])
}

@Test func memoryContextStaysOutOfTheBotRowPreviewAndResumedTurn() throws {
    let rows = try imageMemoryRows(caption: typed)
    let stored = try #require(rows.first?.content)
    var transcript = Transcript(history: rows.filter { $0.role == "user" })
    #expect(transcript.preview?.text == typed)
    transcript.begin(remote: stored, displayKind: nil, at: .now)
    #expect(transcript.turns.last?.prompt?.text == typed)
    #expect(transcript.turns.last?.prompt?.attachments.map(\.path) == [imagePath])
}

@Test func textOnlyRowDropsTheMemoryContext() throws {
    let stored = try #require(imageMemoryRows().first?.content)
    let memory = try #require(stored.firstRange(of: "<memory-context>")).lowerBound
    #expect(Prompt(raw: "Plan my week\n" + stored[memory...], sentAt: .now).text == "Plan my week")
    #expect(Prompt(raw: "Plan my week\n<memory-context>\n[System note: cut off", sentAt: .now).text == "Plan my week")
}
