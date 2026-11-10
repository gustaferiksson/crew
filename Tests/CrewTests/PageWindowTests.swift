import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private func recordedHistories() throws -> [(name: String, rows: [HistoryRow])] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let scenarios = try FileManager.default.subpathsOfDirectory(atPath: fixtures.appending(path: "scenarios").path()).filter { $0.hasSuffix(".history.json") }
    let chats = try FileManager.default.contentsOfDirectory(atPath: fixtures.path()).filter { $0.hasSuffix(".history.json") }
    return try scenarios.map { ($0, try decoder.decode([HistoryRow].self, from: Data(contentsOf: fixtures.appending(path: "scenarios/\($0)")))) }
        + chats.map { name in
            let data = try Data(contentsOf: fixtures.appending(path: name))
            return try (name, (try? decoder.decode(HistoryFile.self, from: data).messages) ?? decoder.decode([HistoryRow].self, from: data))
        }
}

private func shape(_ turn: Turn) -> String {
    "\(turn.prompt?.text ?? "-")|\(turn.notice ?? "-")|\(turn.agentMessage?.sender ?? "-")|\(turn.outgoingMessage?.handle ?? "-")|\(turn.delivery ?? "-")|\(turn.reply)"
}

@MainActor @Test func everyCutOfARecordedChatWithAPromptShowsTheSameRowsAsTheWholeChat() throws {
    var mismatches: [String] = []
    for (name, recorded) in try recordedHistories() {
        let rows = recorded.sorted { $0.id < $1.id }
        let whole = Transcript(history: rows).visible.turns.map(shape)
        for cut in rows.indices.dropFirst() where rows[cut...].contains(where: { $0.role == "user" && AgentMessage($0.displayContent ?? $0.content ?? "") == nil && deliveryProcess(in: $0.displayContent ?? $0.content ?? "") == nil }) {
            let window = Transcript(window: Array(rows[cut...])).visible.turns.map(shape)
            guard Array(whole.suffix(window.count)) != window else { continue }
            mismatches.append("\(name) cut \(cut): window \(window.count) rows \(window.prefix(2)) vs whole \(whole.suffix(window.count).prefix(2))")
        }
    }
    #expect(mismatches.isEmpty)
}
