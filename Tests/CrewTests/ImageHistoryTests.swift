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
    #expect(transcript.visible.lastMessage?.text == "I see a chat app with an approval dialog waiting for an answer.")
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
    #expect(transcript.visible.lastMessage?.text == typed)
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

@Test func serverPreviewFallbackDropsTheMemoryContext() throws {
    let stored = try #require(imageMemoryRows().first?.content)
    let memory = try #require(stored.firstRange(of: "<memory-context>")).lowerBound
    let shaped = ("Thanks\n" + stored[memory...]).replacingOccurrences(of: "\n", with: " ")
    let preview = String(shaped.prefix(60)) + "..."
    let profile: [String: Any] = ["name": "default", "is_default": true, "has_avatar": false, "canonical_session": ["id": "s1", "resolved_id": "s1", "preview": preview]]
    let roster = try JSONDecoder().decode(Roster.self, from: JSONSerialization.data(withJSONObject: ["profiles": [profile]]))
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: roster.profiles)
    let bot = try #require(store.bots.first)
    #expect(ChatSessions().summary(of: bot, in: store).preview == "Thanks")
}

@Test func botRowPreviewShowsRepliesWithoutMarkdownMarks() throws {
    let preview = "**Saturday still looks best, but aim for 13:00–14:00, not the morning.** I checked _dew point_, `wind` and [the forecast](https://yr.no)..."
    let profile: [String: Any] = ["name": "alfred", "is_default": false, "has_avatar": false, "canonical_session": ["id": "s1", "resolved_id": "s1", "preview": preview]]
    let roster = try JSONDecoder().decode(Roster.self, from: JSONSerialization.data(withJSONObject: ["profiles": [profile]]))
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: roster.profiles)
    let bot = try #require(store.bots.first)
    #expect(ChatSessions().summary(of: bot, in: store).preview == "Saturday still looks best, but aim for 13:00–14:00, not the morning. I checked dew point, wind and the forecast...")
}
