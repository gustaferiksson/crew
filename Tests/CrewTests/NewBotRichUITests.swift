import Foundation
import Synchronization
import Testing

nonisolated private final class SkillStub: URLProtocol {
    static let requests = Mutex<[String]>([])
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SkillStub.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let line = "\(request.httpMethod ?? "GET") \(url.path())?\(url.query() ?? "")"
        SkillStub.requests.withLock { $0.append(line) }
        let broken = line.contains("crew-test-broken")
        let status = broken ? 500 : url.path() == "/api/skills/content" ? 404 : 200
        let reply = broken ? #"{"detail":"disk full"}"# : status == 404 ? #"{"detail":"not found"}"# : #"{"ok":true}"#
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private let server = URL(string: "https://hermes.example.com")!
private let gateway = Gateway(server: server, urlSession: SkillStub.session) { "" }

private func requests(for profile: String) -> [String] {
    SkillStub.requests.withLock { $0.filter { $0.contains("profile=\(profile)") } }
}

@Test func aNewBotGetsTheCrewUISkillInstalled() async {
    let result = await NewBotOptions().apply(to: "crew-test-rich", cloneFrom: nil, via: gateway, urlSession: SkillStub.session)

    #expect(requests(for: "crew-test-rich").contains { $0.hasPrefix("GET /api/skills/content?name=crew-ui") })
    #expect(SkillStub.requests.withLock { $0.contains("POST /api/skills?") })
    #expect(result.isComplete)
}

@Test func aFailedSkillInstallStillFinishesTheBotWithRichUIOff() async {
    let result = await NewBotOptions().apply(to: "crew-test-broken", cloneFrom: nil, via: gateway, urlSession: SkillStub.session)

    #expect(result.name == "crew-test-broken")
    #expect(result.richUIFailed)
    #expect(!result.isComplete)
    #expect(result.unapplied.isEmpty)
}

@Test func aDuplicateOrRichUIOffSkipsTheInstall() async {
    var off = NewBotOptions()
    off.richUI = false
    _ = await off.apply(to: "crew-test-plain", cloneFrom: nil, via: gateway, urlSession: SkillStub.session)
    _ = await NewBotOptions().apply(to: "crew-test-copy", cloneFrom: "crew-test", via: gateway, urlSession: SkillStub.session)

    #expect(requests(for: "crew-test-plain").isEmpty)
    #expect(requests(for: "crew-test-copy").isEmpty)
}
