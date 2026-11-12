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
        let authorization = url.query()?.contains("include_defaults=false") == true ? "Bearer ${MCP_FILES_API_KEY}" : "Bearer secret"
        let config = #"{"model":{"default":"gpt-6.1-sol"},"mcp_servers":{"files":{"url":"http://host/mcp","headers":{"Authorization":"\#(authorization)"}},"icloud":{"url":"http://host/icloud"}}}"#
        let env = url.query()?.contains("crew-test-keyless") == true ? #"{"OTHER_KEY":{"is_set":true}}"# : #"{"MCP_FILES_API_KEY":{"is_set":true}}"#
        let reply = request.httpMethod == "PUT" ? #"{"ok":true}"# : url.path() == "/api/env" ? env : config
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
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

@Test func copyConnectionsCopiesTheChosenEntriesWithTheirSecretReferences() async throws {
    let server = try #require(URL(string: "https://hermes.invalid"))
    let keyless = try await copyConnections(["files"], from: "default", to: "crew-test-new", on: server, with: ConfigStub.session)
    let requests = ConfigStub.requests.withLock { $0 }.filter { $0.line.contains("profile=default") || $0.line.contains("crew-test-new") }
    #expect(keyless.isEmpty)
    #expect(requests.map(\.line) == ["GET /api/config?profile=default&include_defaults=false", "GET /api/env?profile=crew-test-new", "PUT /api/config?profile=crew-test-new"])
    let body = try JSONDecoder().decode(JSONValue.self, from: try #require(requests.last?.body))
    #expect(body == .object(["config": .object(["mcp_servers": .object([
        "files": .object(["url": .string("http://host/mcp"), "headers": .object(["Authorization": .string("Bearer ${MCP_FILES_API_KEY}")])]),
    ])])]))
}

@Test func copyConnectionsSkipsAConnectionWhoseKeyTheNewBotLacks() async throws {
    let server = try #require(URL(string: "https://hermes.invalid"))
    let keyless = try await copyConnections(["files", "icloud"], from: "vera", to: "crew-test-keyless", on: server, with: ConfigStub.session)
    let requests = ConfigStub.requests.withLock { $0 }.filter { $0.line.contains("vera") || $0.line.contains("crew-test-keyless") }
    #expect(keyless == ["files"])
    #expect(requests.map(\.line) == ["GET /api/config?profile=vera&include_defaults=false", "GET /api/env?profile=crew-test-keyless", "PUT /api/config?profile=crew-test-keyless"])
    let body = try JSONDecoder().decode(JSONValue.self, from: try #require(requests.last?.body))
    #expect(body == .object(["config": .object(["mcp_servers": .object(["icloud": .object(["url": .string("http://host/icloud")])])])]))
}
