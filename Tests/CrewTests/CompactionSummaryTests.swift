import Foundation
import Testing

@Test func hiddenCompactionSummaryNeverShowsAsAReplyOrNote() throws {
    let summary = "[CONTEXT COMPACTION — REFERENCE ONLY] Earlier turns were compacted into the summary below.\n\n" + String(repeating: "The user asked about the deploy; the bot checked the rollout. ", count: 890)
    let stored: [[String: Any]] = [
        ["id": 1, "role": "assistant", "content": summary, "display_kind": "hidden", "_compressed_summary": true, "timestamp": 100.0],
        ["id": 2, "role": "user", "content": "Status?", "timestamp": 110.0],
        ["id": 3, "role": "assistant", "content": "All green.", "timestamp": 120.0],
        ["id": 4, "role": "assistant", "content": summary, "display_kind": "hidden", "_compressed_summary": true, "timestamp": 900.0],
        ["id": 5, "role": "user", "content": "And the logs?", "timestamp": 1000.0],
        ["id": 6, "role": "assistant", "content": summary, "display_kind": "hidden", "_compressed_summary": true, "timestamp": 1010.0],
        ["id": 7, "role": "assistant", "content": "Logs are clean.", "timestamp": 1020.0],
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let shown = Transcript(history: try decoder.decode([HistoryRow].self, from: JSONSerialization.data(withJSONObject: stored))).visible.turns

    try #require(shown.count == 2)
    #expect(shown.map { $0.prompt?.text } == ["Status?", "And the logs?"])
    #expect(shown.map { $0.reply } == ["All green.", "Logs are clean."])
    #expect(shown.allSatisfy { $0.work.isEmpty })
    #expect(shown[0].finishedAt == Date(timeIntervalSince1970: 120))
}
