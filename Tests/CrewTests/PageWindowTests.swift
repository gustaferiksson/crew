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

@MainActor @Test(arguments: [7, 12, 25, 40]) func pagingARecordedChatShowsTheWholeChatsLastTurnsAndKeepsTheShownOnes(size: Int) throws {
    var mismatches: [String] = []
    for (name, recorded) in try recordedHistories() {
        let rows = recorded.sorted { $0.id < $1.id }
        let whole = Transcript(history: rows).visible.turns
        var pages = HistoryPages(size: size)
        pages.merge(latest: Array(rows.suffix(size)))
        var shown: [Turn] = []
        while true {
            let window = pages.transcript.visible.turns
            let startsTurn = pages.rows.contains { $0.role == "user" && AgentMessage($0.displayContent ?? $0.content ?? "") == nil && deliveryProcess(in: $0.displayContent ?? $0.content ?? "") == nil }
            if startsTurn || pages.reachedStart {
                if whole.suffix(window.count).map(shape) != window.map(shape) { mismatches.append("\(name) at \(pages.rows.count) rows: not the whole chat's last turns") }
                if window.suffix(shown.count).map(\.id) != shown.map(\.id) { mismatches.append("\(name) at \(pages.rows.count) rows: a shown turn changed") }
                shown = window
            }
            if pages.reachedStart { break }
            pages.prepend(older: Array(rows.dropLast(pages.rows.count).suffix(size)))
        }
        if pages.transcript.visible.turns.map(\.id) != whole.map(\.id) { mismatches.append("\(name): the start differs from the whole chat") }
    }
    #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
}

@MainActor @Test func aRefetchedLatestPageKeepsTheOlderPagesUnlessItLeavesAGap() throws {
    let rows = try #require(try recordedHistories().map(\.rows).max { $0.count < $1.count }).sorted { $0.id < $1.id }
    try #require(rows.count >= 20)
    var pages = HistoryPages(size: 5)
    pages.merge(latest: Array(rows.dropLast(3).suffix(5)))
    pages.prepend(older: Array(rows.dropLast(8).suffix(5)))
    #expect(pages.rows.map(\.id) == rows.dropLast(3).suffix(10).map(\.id))
    pages.merge(latest: Array(rows.suffix(5)))
    #expect(pages.rows.map(\.id) == rows.suffix(13).map(\.id), "three new rows join the loaded ones")
    #expect(!pages.reachedStart)

    var gapped = HistoryPages(size: 5)
    gapped.merge(latest: Array(rows.prefix(5)))
    gapped.merge(latest: Array(rows.suffix(5)))
    #expect(gapped.rows.map(\.id) == rows.suffix(5).map(\.id), "a page that does not reach the loaded rows replaces them")

    var short = HistoryPages(size: 5)
    short.merge(latest: Array(rows.suffix(4)))
    #expect(short.reachedStart)
}
