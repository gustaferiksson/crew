import Foundation
import Synchronization
import Testing

nonisolated private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

nonisolated private final class ChatStub: URLProtocol {
    static let requests = Mutex<[(limit: Int, offset: Int)]>([])
    static let rows = Mutex(Data())
    static let fails = Mutex(false)
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatStub.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let limit = items.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 500
        let offset = items.first { $0.name == "offset" }?.value.flatMap(Int.init) ?? 0
        ChatStub.requests.withLock { $0.append((limit, offset)) }
        let rows = (try? JSONSerialization.jsonObject(with: ChatStub.rows.withLock { $0 })) as? [[String: Any]] ?? []
        let page = Array(rows.dropLast(offset).suffix(limit))
        let status = ChatStub.fails.withLock { $0 } ? 500 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: ["messages": page])) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

nonisolated private func recordedRows(copies: Int) throws -> [[String: Any]] {
    let page = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appending(path: "chat.long-replies.history.json"))) as? [String: Any]
    let rows = page?["messages"] as? [[String: Any]] ?? []
    return (0..<copies).flatMap { copy in
        rows.map { row in
            var row = row
            row["id"] = copy * 10_000 + (row["id"] as? Int ?? 0)
            if let call = row["tool_call_id"] as? String { row["tool_call_id"] = "c\(copy)-\(call)" }
            if let calls = row["tool_calls"] as? [[String: Any]] { row["tool_calls"] = calls.map { $0.merging(["id": "c\(copy)-\($0["id"] as? String ?? "")"]) { $1 } } }
            return row
        }
    }
}

@MainActor @Suite(.serialized) struct HistoryPagingTests {
    private let bot = Bot(
        name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false,
        canonicalSession: CanonicalSession(id: StoredSessionID(rawValue: "s"), resolvedID: StoredSessionID(rawValue: "s"), preview: nil, lastActive: .now, messageCount: 490),
        meta: BotMeta(), metaRevision: 1
    )

    private func settled(_ chat: ChatSession, until done: () -> Bool) async throws {
        for _ in 0..<200 where !done() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func anOpenChatFetchesOnlyTheLatestPageAndLoadsOlderPagesOnRequest() async throws {
        let rows = try recordedRows(copies: 14)
        ChatStub.rows.withLock { $0 = (try? JSONSerialization.data(withJSONObject: rows)) ?? Data() }
        ChatStub.requests.withLock { $0 = [] }
        ChatStub.fails.withLock { $0 = false }
        let gateway = Gateway(server: URL(string: "https://hermes.invalid")!, urlSession: ChatStub.session) { throw CancellationError() }
        let chat = ChatSession(bot: bot, gateway: gateway, urlSession: ChatStub.session)

        chat.sync(to: ReadPosition(session: "s", messages: 491))
        try await settled(chat) { !chat.visible.turns.isEmpty }
        #expect(ChatStub.requests.withLock { $0.map(\.limit) } == [100], "the open chat fetched more than one page")
        #expect(chat.earlier == .more)
        let latest = chat.visible.turns.map(\.id)

        chat.loadEarlier()
        try await settled(chat) { chat.earlier != .loading }
        #expect(ChatStub.requests.withLock { $0.last.map { [$0.limit, $0.offset] } } == [100, 100])
        let paged = chat.visible.turns.map(\.id)
        #expect(paged.count > latest.count && Array(paged.suffix(latest.count)) == latest, "the older page did not land above the shown turns")

        let grown = try rows + recordedRows(copies: 15).suffix(35)
        ChatStub.rows.withLock { $0 = (try? JSONSerialization.data(withJSONObject: grown)) ?? Data() }
        chat.sync(to: ReadPosition(session: "s", messages: 525))
        try await settled(chat) { chat.visible.turns.count > paged.count }
        #expect(ChatStub.requests.withLock { $0.last.map { [$0.limit, $0.offset] } } == [100, 0], "the catch-up fetched more than the latest page")
        #expect(Array(chat.visible.turns.map(\.id).prefix(paged.count)) == paged, "the catch-up dropped the older pages")

        ChatStub.fails.withLock { $0 = true }
        chat.loadEarlier()
        try await settled(chat) { chat.earlier != .loading }
        #expect(chat.earlier == .failed)
        ChatStub.fails.withLock { $0 = false }
        for _ in 0..<10 where chat.earlier != .complete {
            chat.loadEarlier()
            try await settled(chat) { chat.earlier != .loading }
        }
        #expect(chat.earlier == .complete)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let whole = Transcript(history: try decoder.decode([HistoryRow].self, from: ChatStub.rows.withLock { $0 })).visible.turns.map(\.id)
        #expect(chat.visible.turns.map(\.id) == whole, "the start of the chat differs from the whole history")
    }
}
