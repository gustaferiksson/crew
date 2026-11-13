import Foundation
import Synchronization
import Testing

nonisolated private let rawConfig = (try? Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/mcp/config-raw.v0.23.1.json"))) ?? Data()

nonisolated private final class RawConfigStub: URLProtocol {
    static let requests = Mutex<[(line: String, body: Data?)]>([])
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RawConfigStub.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let query = url.query() ?? ""
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
        RawConfigStub.requests.withLock { $0.append(("\(request.httpMethod ?? "GET") \(url.path())?\(query)", body)) }
        let expanded = String(decoding: rawConfig, as: UTF8.self).replacing("${MCP_WIKIKEY_API_KEY}", with: "plaintext-key")
        let reply: String
        if url.path() == "/api/config" {
            reply = query.contains("crew-test-gone") ? #"{"model":"gpt-6.1-sol"}"# : query.contains("include_defaults=false") ? String(decoding: rawConfig, as: UTF8.self) : expanded
        } else if url.path() == "/api/mcp/servers", request.httpMethod == "GET" {
            reply = #"{"servers":[{"name":"wikikey","transport":"http","url":"https://mcp.deepwiki.com/mcp","command":null,"args":[],"auth":"header","enabled":true,"source":"config","plugin":null},{"name":"deepwiki","transport":"http","url":"https://mcp.deepwiki.com/mcp","command":null,"args":[],"auth":null,"enabled":true,"source":"config","plugin":null}]}"#
        } else if url.path().hasSuffix("/test") {
            reply = #"{"ok":true,"tools":[{"name":"ask_wiki_question","description":"Ask"}]}"#
        } else {
            reply = #"{"ok":true}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func recorded() throws -> [String: JSONValue] {
    guard case .object(let config) = try JSONDecoder().decode(JSONValue.self, from: rawConfig), case .object(let servers) = config["mcp_servers"] ?? .null else { return [:] }
    return servers
}

private func sentServers(_ profile: String) throws -> [String: JSONValue]? {
    let put = RawConfigStub.requests.withLock { $0 }.last { $0.line == "PUT /api/mcp/servers?profile=\(profile)" }
    guard let body = put?.body else { return nil }
    guard case .object(let fields) = try JSONDecoder().decode(JSONValue.self, from: body), case .object(let servers) = fields["servers"] ?? .null else { return nil }
    #expect(fields["profile"] == .string(profile))
    return servers
}

private func rawMembers(_ text: String) -> [(key: Substring, value: Substring)] {
    jsonMembers(jsonMembers(text[...]).first { $0.key == "\"mcp_servers\"" || $0.key == "\"servers\"" }?.value ?? "")
}

private func sentText(_ profile: String) -> String {
    let body = RawConfigStub.requests.withLock { $0 }.last { $0.line == "PUT /api/mcp/servers?profile=\(profile)" }?.body
    return String(decoding: body ?? Data(), as: UTF8.self)
}

private func loadedStore(_ profile: String) async throws -> (BotConnections, URL) {
    let server = try #require(URL(string: "https://hermes.invalid"))
    let store = BotConnections(profile: profile)
    await store.load(on: server, with: RawConfigStub.session)
    return (store, server)
}

@Test func aToolSwitchChangesOnlyThatEntryAndKeepsSecretReferences() async throws {
    let (store, server) = try await loadedStore("crew-test-tool")
    await store.setTool("ask_wiki_question", on: false, for: "deepwiki", on: server, with: RawConfigStub.session)

    let raw = try recorded()
    let sent = try #require(try sentServers("crew-test-tool"))
    #expect(RawConfigStub.requests.withLock { $0 }.contains { $0.line == "GET /api/config?profile=crew-test-tool&include_defaults=false" })
    #expect(store.failures["deepwiki"] == nil)
    let recordedMembers = rawMembers(String(decoding: rawConfig, as: UTF8.self))
    let sentMembers = rawMembers(sentText("crew-test-tool"))
    #expect(sentMembers.map(\.key) == ["\"wikikey\"", "\"deepwiki\""])
    #expect(sentMembers.map(\.key) == recordedMembers.map(\.key))
    #expect(sentMembers.first?.value == recordedMembers.first?.value)
    #expect(jsonMembers(sentMembers[1].value).map(\.key) == ["\"url\"", "\"enabled\"", "\"tools\""])
    guard case .object(var expected) = raw["deepwiki"] ?? .null else { return #expect(Bool(false)) }
    expected["tools"] = .object(["exclude": .array([.string("ask_wiki_question")])])
    #expect(sent["deepwiki"] == .object(expected))
    #expect(store.servers?.first { $0.name == "deepwiki" }?.offers("ask_wiki_question") == false)
}

@Test func anAddressChangeKeepsTheEditedEntrysSecretReference() async throws {
    let (store, server) = try await loadedStore("crew-test-address")
    await store.changeAddress("https://mcp.example.com/mcp", for: "wikikey", on: server, with: RawConfigStub.session)

    let raw = try recorded()
    let sent = try #require(try sentServers("crew-test-address"))
    let recordedMembers = rawMembers(String(decoding: rawConfig, as: UTF8.self))
    let sentMembers = rawMembers(sentText("crew-test-address"))
    #expect(sentMembers.map(\.key) == recordedMembers.map(\.key))
    #expect(sentMembers.last?.value == recordedMembers.last?.value)
    #expect(jsonMembers(sentMembers[0].value).map(\.key) == ["\"headers\"", "\"url\""])
    #expect(sent["wikikey"] == .object([
        "url": .string("https://mcp.example.com/mcp"),
        "headers": .object(["Authorization": .string("Bearer ${MCP_WIKIKEY_API_KEY}")]),
    ]))
    #expect(!sentText("crew-test-address").contains("plaintext-key"))
    #expect(raw.count == sent.count)
}

@Test func noWholeMapWriteWithoutTheConnectionInAFreshRead() async throws {
    let (store, server) = try await loadedStore("crew-test-gone")
    await store.setTool("ask_wiki_question", on: false, for: "deepwiki", on: server, with: RawConfigStub.session)

    #expect(try sentServers("crew-test-gone") == nil)
    #expect(store.failures["deepwiki"] == "deepwiki was removed on the server.")
}

@Test func aKeyChangeRefusesHeadersThatArentOneBearerReference() async throws {
    let (store, server) = try await loadedStore("crew-test-key")
    let gateway = Gateway(server: server, urlSession: RawConfigStub.session) { "" }
    await store.changeAPIKey("new", for: "deepwiki", on: server, with: RawConfigStub.session, gateway: gateway)

    #expect(store.failures["deepwiki"] == "deepwiki's headers were written by hand. Change its key on the server.")
}

@Test func toolSwitchesFollowDesktopsFilterRules() {
    let tools = { (filter: JSONValue) in settingTool("b", on: false, in: ["url": .string("u"), "tools": filter])["tools"] }
    #expect(tools(.object(["include": .array([.string("a"), .string("b")])])) == .object(["include": .array([.string("a")])]))
    #expect(tools(.object(["include": .string("b")])) == .object(["include": .array([])]))
    #expect(tools(.object(["exclude": .array([.string("a")])])) == .object(["exclude": .array([.string("a"), .string("b")])]))
    #expect(settingTool("a", on: true, in: ["tools": .object(["exclude": .array([.string("a")])])]) == [:])
    #expect(settingTool("a", on: true, in: ["tools": .object(["include": .array([])])]) == ["tools": .object(["include": .array([.string("a")])])])

    var server = MCPServer(name: "deepwiki", transport: "http", url: "u", command: nil, args: [], auth: nil, enabled: true, source: "config", plugin: nil)
    server.tools = .object(["exclude": .array([.string("read_wiki_s*"), .string("ask_wiki_question")])])
    #expect(!server.canSwitch("read_wiki_structure"))
    #expect(server.canSwitch("ask_wiki_question"))
    #expect(server.canSwitch("read_wiki_contents"))
}
