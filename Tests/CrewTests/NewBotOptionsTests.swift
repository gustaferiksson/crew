import Foundation
import Synchronization
import Testing

nonisolated private final class ConfigStub: URLProtocol {
    static let requests = Mutex<[(line: String, body: Data?)]>([])
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConfigStub.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let body = request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
        ConfigStub.requests.withLock { $0.append(("\(request.httpMethod ?? "GET") \(url.path())?\(url.query() ?? "")", body)) }
        let config = #"{"model":{"default":"gpt-6.1-sol"},"mcp_servers":{"files":{"url":"http://host/mcp","headers":{"Authorization":"Bearer secret"}},"icloud":{"url":"http://host/icloud"}}}"#
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((request.httpMethod == "PUT" ? #"{"ok":true}"# : config).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func encoded(_ profile: NewProfile) throws -> [String: JSONValue] {
    try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(profile))
}

@Test func untouchedOptionsCreateTheSameProfileAsBefore() throws {
    let profile = NewBotOptions().profile(name: "ada", description: nil, soul: nil, cloneFrom: nil)
    #expect(try encoded(profile) == ["name": .string("ada")])
}

@Test func keysAndSkillsMapToHermesCreateParams() throws {
    var options = NewBotOptions()
    options.copyKeys = false
    options.bundledSkills = false
    #expect(try encoded(options.profile(name: "ada", description: nil, soul: nil, cloneFrom: nil)) == [
        "name": .string("ada"), "mirror_credentials": .bool(false), "no_skills": .bool(true),
    ])
    #expect(try encoded(options.profile(name: "ada", description: nil, soul: nil, cloneFrom: "marlow")) == [
        "name": .string("ada"), "clone_from": .string("marlow"), "mirror_credentials": .bool(false),
    ])
}

@Test func onlyFlippedToolsetsAreSaved() {
    let web = ProfileCapability(name: "web", label: nil, description: nil, transport: nil, toolCount: 2, enabled: true)
    let terminal = ProfileCapability(name: "terminal", label: nil, description: nil, transport: nil, toolCount: 2, enabled: false)
    var options = NewBotOptions(toolsets: [web, terminal], loadedToolsets: [web, terminal])
    #expect(options.changedToolsets.isEmpty)
    options.toolsets[1].enabled = true
    #expect(options.changedToolsets.map(\.name) == ["terminal"])
}

@Test func copyConnectionsWritesOnlyTheChosenEntriesToTheNewBot() async throws {
    let server = try #require(URL(string: "https://hermes.invalid"))
    try await copyConnections(["files"], from: "default", to: "crew-test-new", on: server, with: ConfigStub.session)
    let requests = ConfigStub.requests.withLock { $0 }
    #expect(requests.map(\.line) == ["GET /api/config?profile=default", "PUT /api/config?profile=crew-test-new"])
    let body = try JSONDecoder().decode(JSONValue.self, from: try #require(requests.last?.body))
    #expect(body == .object(["config": .object(["mcp_servers": .object([
        "files": .object(["url": .string("http://host/mcp"), "headers": .object(["Authorization": .string("Bearer secret")])]),
    ])])]))
}
