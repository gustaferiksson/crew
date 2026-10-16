import Foundation
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/stale-exchange")

private func recorded<Value: Decodable>(_ name: String, as type: Value.Type, keys: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.keyDecodingStrategy = keys
    return try decoder.decode(type, from: Data(contentsOf: scenario.appending(path: "\(name).json")))
}

private func history(_ name: String) throws -> [HistoryRow] {
    try recorded(name, as: [HistoryRow].self, keys: .convertFromSnakeCase)
}

private func roster() throws -> [Bot] {
    try recorded("profiles.after", as: Roster.self).profiles
}

nonisolated private final class RecordedHistory: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let profile = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "profile" }?.value } ?? ""
        let folder = profile == "test-bot" ? "stale-exchange" : "open-target"
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/\(folder)/\(profile).history.json")
        guard let url = request.url, url.path().contains("/messages"), let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
              let rows = try? Data(contentsOf: file)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"messages":"#.utf8) + rows + Data("}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Test func targetChatShowsEveryExchangeUpToTheLatest() throws {
    let rows = try history("test-bot.history")
    let shown = Transcript(history: rows).visible.turns
    let starts = rows.filter { $0.role == "user" && AgentMessage($0.content ?? "") != nil }.map { Date(timeIntervalSince1970: $0.timestamp) }
    #expect(shown.count == 5)
    #expect(shown.allSatisfy { $0.agentMessage?.sender == "Crew Test" && $0.prompt == nil && $0.reply.isEmpty })
    #expect(shown.map(\.startedAt) == starts)
}

@Test func targetRowPreviewAndTimePointAtTheLastRow() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try roster())
    store.showPreview(of: "test-bot", from: try history("test-bot.preview"))
    let lastRow = try #require(Transcript(history: try history("test-bot.history")).visible.turns.last)
    let lastActive = try #require(store.bots.first { $0.name == "test-bot" }?.canonicalSession?.lastActive)
    #expect(store.previews["test-bot"] == "Message from Crew Test")
    #expect(abs(lastActive.timeIntervalSince(lastRow.startedAt)) < 1)
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

@Test func openTargetChatCatchesUpWithRowsWrittenOutsideItsSession() async throws {
    let bots = try roster()
    let bot = try #require(bots.first { $0.name == "test-bot" })
    let session = try openChat(bot)
    let chats = ChatSessions(fixture: ["test-bot": session])
    let stale = try #require(bot.canonicalSession?.position)
    chats.sync(with: bots)
    #expect(session.transcript.turns.isEmpty)
    session.sync(to: ReadPosition(session: stale.session, messages: stale.messages + 1))
    try await settle(session)
    #expect(session.transcript.visible.turns.count == 5)
    #expect(session.transcript.preview == "Message from Crew Test")
}

@Test func senderChatHidesTheFollowUpAfterAnEarlierDeliveryDied() throws {
    let shown = Transcript(history: try history("crew-test.history")).visible.turns
    #expect(shown.map { $0.prompt?.text ?? $0.reply } == [
        "@test-bot what time is it?",
        "@test-bot hi",
        "@test-bot: “Hello! 👋”",
    ])
    #expect(shown.allSatisfy { $0.delivery == nil })
}

@Test func senderRowPreviewIsTheRelay() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try roster())
    store.showPreview(of: "crew-test", from: try history("crew-test.preview"))
    #expect(store.previews["crew-test"] == "@test-bot: “Hello! 👋”")
    #expect(Transcript(history: try history("crew-test.history")).preview == store.previews["crew-test"])
}

@Test func windowWithoutAPromptFallsBackToTheServerPreview() throws {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try roster())
    store.showPreview(of: "test-bot", from: try history("test-bot.preview").filter { $0.role != "user" })
    #expect(store.previews["test-bot"] == nil)
    #expect(store.bots.first { $0.name == "test-bot" }?.canonicalSession?.preview?.isEmpty == false)
}

@Test func freshTargetChatOpenDuringTheExchangeShowsIt() async throws {
    let folder = scenario.deletingLastPathComponent().appending(path: "open-target")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let before = try decoder.decode(Roster.self, from: Data(contentsOf: folder.appending(path: "profiles.before.json"))).profiles
    let after = try decoder.decode(Roster.self, from: Data(contentsOf: folder.appending(path: "profiles.after.json"))).profiles
    let session = try openChat(try #require(before.first { $0.name == "crew-test-peer" }))
    let chats = ChatSessions(fixture: ["crew-test-peer": session])
    chats.sync(with: after)
    try await settle(session)
    #expect(session.transcript.visible.turns.count == 1)
    #expect(session.transcript.visible.turns.first?.agentMessage?.sender == "Crew Test")
    #expect(session.transcript.preview == "Message from Crew Test")
}
