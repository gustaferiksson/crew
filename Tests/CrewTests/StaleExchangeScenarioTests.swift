import Foundation
import Testing

private let scenarios = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios")

private func recorded<Value: Decodable>(_ name: String, in scenario: String = "stale-exchange", as type: Value.Type) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = type == [HistoryRow].self ? .convertFromSnakeCase : .useDefaultKeys
    return try decoder.decode(type, from: Data(contentsOf: scenarios.appending(path: "\(scenario)/\(name).json")))
}

nonisolated private final class RecordedHistory: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let profile = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "profile" }?.value } ?? ""
        let scenarios = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios")
        let rows = ["stale-exchange", "open-target"].lazy.compactMap { try? Data(contentsOf: scenarios.appending(path: "\($0)/\(profile).history.json")) }.first
        guard let url = request.url, url.path().contains("/messages"), let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil), let rows else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"messages":"#.utf8) + rows + Data("}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func openChat(_ bot: Bot) throws -> ChatSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordedHistory.self]
    let server = try #require(URL(string: "https://hermes.invalid"))
    return ChatSession(bot: bot, gateway: Gateway(server: server, urlSession: .shared) { throw CancellationError() }, urlSession: URLSession(configuration: configuration))
}

private func settle(_ session: ChatSession) async throws {
    for _ in 0..<100 where session.transcript.turns.isEmpty {
        try await Task.sleep(for: .milliseconds(20))
    }
}

@Test func targetChatShowsEveryExchangeUpToTheLatest() throws {
    let rows = try recorded("test-bot.history", as: [HistoryRow].self)
    let shown = Transcript(history: rows).visible.turns
    let starts = rows.filter { $0.role == "user" && AgentMessage($0.content ?? "") != nil }.map { Date(timeIntervalSince1970: $0.timestamp) }
    #expect(shown.count == 5)
    #expect(shown.allSatisfy { $0.agentMessage?.sender == "Crew Test" && $0.prompt == nil && $0.reply.isEmpty })
    #expect(shown.map(\.startedAt) == starts)
}

@Test func targetRowPreviewAndTimePointAtTheLastRow() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.after", as: Roster.self).profiles)
    store.showPreview(of: "test-bot", from: try recorded("test-bot.preview", as: [HistoryRow].self))
    let lastRow = try #require(Transcript(history: try recorded("test-bot.history", as: [HistoryRow].self)).visible.turns.last)
    let lastActive = try #require(store.bots.first { $0.name == "test-bot" }?.canonicalSession?.lastActive)
    #expect(store.previews["test-bot"] == "Message from Crew Test")
    #expect(abs(lastActive.timeIntervalSince(lastRow.startedAt)) < 1)
}

@Test func openTargetChatRefetchesWhenThePositionMoves() async throws {
    let bots = try recorded("profiles.after", as: Roster.self).profiles
    let bot = try #require(bots.first { $0.name == "test-bot" })
    let rows = try recorded("test-bot.history", as: [HistoryRow].self)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordedHistory.self]
    let session = ChatSession(fixture: bot, transcript: Transcript(history: rows.filter { $0.id <= 21 }), todos: [], urlSession: URLSession(configuration: configuration))
    let chats = ChatSessions(fixture: ["test-bot": session])
    chats.sync(with: bots)
    try await Task.sleep(for: .milliseconds(300))
    #expect(session.transcript.visible.turns.count == 4)
    let position = try #require(bot.canonicalSession?.position)
    session.sync(to: ReadPosition(session: position.session, messages: position.messages + 1))
    for _ in 0..<100 where session.transcript.visible.turns.count == 4 {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(session.transcript.visible.turns.count == 5)
    #expect(session.transcript.visible.turns.last?.startedAt == Date(timeIntervalSince1970: try #require(rows.first { $0.id == 22 }).timestamp))
    #expect(session.transcript.preview == "Message from Crew Test")
}

@Test func freshTargetChatOpenDuringTheExchangeShowsIt() async throws {
    let before = try recorded("profiles.before", in: "open-target", as: Roster.self).profiles
    let session = try openChat(try #require(before.first { $0.name == "crew-test-peer" }))
    ChatSessions(fixture: ["crew-test-peer": session]).sync(with: try recorded("profiles.after", in: "open-target", as: Roster.self).profiles)
    try await settle(session)
    #expect(session.transcript.visible.turns.count == 1)
    #expect(session.transcript.visible.turns.first?.agentMessage?.sender == "Crew Test")
    #expect(session.transcript.preview == "Message from Crew Test")
}

@Test func refetchKeepsLocalFailures() {
    let start = Date(timeIntervalSince1970: 1_792_180_000)
    let failed = Turn(id: "a", prompt: Prompt(text: "hi", sentAt: start), status: .error, startedAt: start, failure: "Network down")
    let unsent = Turn(id: "b", prompt: Prompt(text: "again", sentAt: start), status: .error, startedAt: start, failure: "Not sent")
    var reloaded = Transcript(turns: [Turn(id: "a", prompt: Prompt(text: "hi", sentAt: start), status: .complete, startedAt: start)])
    reloaded.keepFailures(from: Transcript(turns: [failed, unsent]))
    #expect(reloaded.turns.map(\.id) == ["a", "b"])
    #expect(reloaded.turns.map(\.status) == [.error, .error])
    #expect(reloaded.turns.first?.failure == "Network down")
}

@Test func senderChatHidesTheFollowUpAfterAnEarlierDeliveryDied() throws {
    let shown = Transcript(history: try recorded("crew-test.history", as: [HistoryRow].self)).visible.turns
    #expect(shown.map { $0.prompt?.text ?? $0.reply } == [
        "@test-bot what time is it?",
        "@test-bot hi",
        "@test-bot: “Hello! 👋”",
    ])
    #expect(shown.allSatisfy { $0.delivery == nil })
}

@Test func followUpStillShowsWhenOnlyAnEarlierMentionWasAnswered() throws {
    let rows = try recorded("crew-test.history", as: [HistoryRow].self)
    let again = rows.filter { (388...391).contains($0.id) || (394...395).contains($0.id) }.map { row in
        HistoryRow(id: row.id + 100, role: row.role, content: row.content, toolCallId: row.toolCallId.map { "\($0)-again" }, toolCalls: row.toolCalls?.map { HistoryRow.Call(id: "\($0.id)-again", function: $0.function) }, timestamp: row.timestamp + 600, reasoning: row.reasoning, reasoningContent: row.reasoningContent, displayKind: row.displayKind, displayContent: row.displayContent, displayCommentary: row.displayCommentary, displayReasoning: row.displayReasoning)
    }
    let shown = Transcript(history: rows.filter { (388...393).contains($0.id) } + again).visible.turns
    #expect(shown.last?.delivery != nil)
}

@Test func failedFollowUpShowsEvenAfterAReplyFromTheSameBot() throws {
    let rows = try recorded("crew-test.history", as: [HistoryRow].self)
    let again = rows.filter { (388...391).contains($0.id) || $0.id == 394 }.map { row in
        HistoryRow(id: row.id + 100, role: row.role, content: row.content?.replacingOccurrences(of: "completed normally (exit code 0)", with: "exited (exit code 1)"), toolCallId: row.toolCallId.map { "\($0)-again" }, toolCalls: row.toolCalls?.map { HistoryRow.Call(id: "\($0.id)-again", function: $0.function) }, timestamp: row.timestamp, reasoning: row.reasoning, reasoningContent: row.reasoningContent, displayKind: row.displayKind, displayContent: row.displayContent, displayCommentary: row.displayCommentary, displayReasoning: row.displayReasoning)
    }
    let ordered = rows.filter { (388...391).contains($0.id) } + again.filter { $0.id < 494 } + rows.filter { (392...393).contains($0.id) } + again.filter { $0.id == 494 }
    let transcript = Transcript(history: ordered.enumerated().map { index, row in
        HistoryRow(id: index + 1, role: row.role, content: row.content, toolCallId: row.toolCallId, toolCalls: row.toolCalls, timestamp: row.timestamp, reasoning: row.reasoning, reasoningContent: row.reasoningContent, displayKind: row.displayKind, displayContent: row.displayContent, displayCommentary: row.displayCommentary, displayReasoning: row.displayReasoning)
    })
    #expect(transcript.turns.last?.deliveryFailed == true)
    #expect(transcript.visible.turns.last?.delivery != nil)
    #expect(Transcript(history: rows).turns.contains { $0.delivery != nil && !$0.deliveryFailed })
}

@Test func senderRowPreviewIsTheRelay() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.after", as: Roster.self).profiles)
    store.showPreview(of: "crew-test", from: try recorded("crew-test.preview", as: [HistoryRow].self))
    #expect(store.previews["crew-test"] == "@test-bot: “Hello! 👋”")
    #expect(Transcript(history: try recorded("crew-test.history", as: [HistoryRow].self)).preview == store.previews["crew-test"])
}

@Test func windowWithoutAPromptFallsBackToTheServerPreview() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.after", as: Roster.self).profiles)
    store.showPreview(of: "test-bot", from: try recorded("test-bot.preview", as: [HistoryRow].self).filter { $0.role != "user" })
    #expect(store.previews["test-bot"] == nil)
    #expect(store.bots.first { $0.name == "test-bot" }?.canonicalSession?.preview == "Crew Test received my greeting.")
}
