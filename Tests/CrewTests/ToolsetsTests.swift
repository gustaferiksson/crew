import Foundation
import Testing

nonisolated private final class ToolsetsFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/tools.toolsets.v0.21.7.json")
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
              let data = try? Data(contentsOf: file)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Test func toolsetsFixtureDecodes() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ToolsetsFixture.self]
    let server = try #require(URL(string: "https://hermes.invalid"))
    let loaded = try await toolsets(of: "crew-test", on: server, with: URLSession(configuration: configuration))
    #expect(loaded.count == 28)
    #expect(loaded.filter(\.enabled).count == 21)
}
