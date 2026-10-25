import Foundation
import Synchronization
import Testing

nonisolated private final class SessionsServer: URLProtocol {
    static let sent = Mutex<[(method: String, url: URL, body: Data)]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        let body = request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable, case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 { data.append(buffer, count: count) }
            return data
        }
        let method = request.httpMethod ?? "GET"
        Self.sent.withLock { $0.append((method, url, body ?? Data())) }
        let reply = if method == "GET" {
            #"{"id":"20261001_090000_aaaaaa","runtime_revision":4,"title":"Bot Chat"}"#
        } else {
            #"{"ok":true,"revision":5}"#
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func stubbed() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SessionsServer.self]
    return URLSession(configuration: configuration)
}

@Suite(.serialized) struct StartNewChatTests {
    @Test func startNewChatArchivesTheBotChatUnderAnotherTitleAtItsRevision() async throws {
        SessionsServer.sent.withLock { $0 = [] }
        let server = try #require(URL(string: "https://hermes.invalid"))
        try await retireBotChat(StoredSessionID(rawValue: "20261001_090000_aaaaaa"), profile: "crew-test", on: server, with: stubbed(), at: Date(timeIntervalSince1970: 1_793_000_000))
        let sent = SessionsServer.sent.withLock { $0 }
        let body = try #require(sent.last?.body)
        let patch = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent.map(\.method) == ["GET", "PATCH"])
        #expect(sent.allSatisfy { $0.url.path() == "/api/sessions/20261001_090000_aaaaaa" })
        #expect(sent.first?.url.query()?.contains("profile=crew-test") == true)
        #expect(patch["profile"] as? String == "crew-test")
        #expect(patch["archived"] as? Bool == true)
        #expect(patch["hidden"] as? Bool == false)
        #expect(patch["expected_revision"] as? Int == 4)
        #expect((patch["request_id"] as? String)?.isEmpty == false)
        let title = try #require(patch["title"] as? String)
        #expect(title.hasPrefix("Bot Chat "))
        #expect(title != "Bot Chat" && !title.contains("#"))
    }
}
