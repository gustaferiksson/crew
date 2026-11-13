import Foundation
import Synchronization
import Testing

nonisolated private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/mcp")
nonisolated private let sourceConfig = String(decoding: (try? Data(contentsOf: fixtures.appending(path: "config-raw.v0.23.1.json"))) ?? Data(), as: UTF8.self)
nonisolated private let targetConfig = String(decoding: (try? Data(contentsOf: fixtures.appending(path: "config-raw-target.v0.23.1.json"))) ?? Data(), as: UTF8.self)

nonisolated private final class AddStub: URLProtocol {
    static let requests = Mutex<[(line: String, body: Data?)]>([])
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AddStub.self]
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
        AddStub.requests.withLock { $0.append(("\(request.httpMethod ?? "GET") \(url.path())?\(query)", body)) }
        let raw = query.contains("include_defaults=false")
        let profile = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "profile" }?.value ?? ""
        let target = [
            "crew-test-fresh": #"{"model":"gpt-6.1-sol"}"#,
            "crew-test-odd": #"{"mcp_servers":["deepwiki"]}"#,
            "crew-test-same": #"{"mcp_servers":{"deepwiki":{"url":"https://mcp.deepwiki.com/mcp"}}}"#,
            "crew-test-other": #"{"mcp_servers":{"deepwiki":{"url":"https://example.com/mcp"}}}"#,
        ][profile] ?? targetConfig
        let reply: String
        if url.path() == "/api/config" {
            let config = profile == "crew-test" ? sourceConfig : target
            reply = raw ? config : config.replacing("${MCP_WIKIKEY_API_KEY}", with: "plaintext-key").replacing("${MCP_NOTES_API_KEY}", with: "plaintext-notes")
        } else if url.path() == "/api/env" {
            reply = profile == "crew-test-keyless" ? #"{"OTHER_KEY":{"is_set":true}}"# : #"{"MCP_WIKIKEY_API_KEY":{"is_set":true},"MCP_NOTES_API_KEY":{"is_set":true}}"#
        } else {
            reply = #"{"ok":true}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func add(_ name: String, to profile: String) async throws -> ConnectionAddOutcome {
    let server = try #require(URL(string: "https://hermes.invalid"))
    let entry = try #require(try rawServerEntry(name, in: try await rawConfigText(of: "crew-test", on: server, with: AddStub.session)))
    return await addConnection(name, entry: entry, to: profile, on: server, with: AddStub.session)
}

private func sentText(_ profile: String) -> String? {
    AddStub.requests.withLock { $0 }.last { $0.line == "PUT /api/mcp/servers?profile=\(profile)" }.map { String(decoding: $0.body ?? Data(), as: UTF8.self) }
}

private func sentServers(_ profile: String) throws -> [String: JSONValue]? {
    guard let text = sentText(profile), case .object(let fields) = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), case .object(let servers) = fields["servers"] ?? .null else { return nil }
    return servers
}

@Test func aConnectionIsAddedWithItsKeyReferenceNeverTheResolvedKey() async throws {
    #expect(try await add("wikikey", to: "crew-test-keyed") == .added)

    let text = try #require(sentText("crew-test-keyed"))
    let servers = try #require(try sentServers("crew-test-keyed"))
    #expect(!text.contains("plaintext-key"))
    #expect(servers["wikikey"] == .object([
        "headers": .object(["Authorization": .string("Bearer ${MCP_WIKIKEY_API_KEY}")]),
        "url": .string("https://mcp.deepwiki.com/mcp"),
    ]))
}

@Test func theTargetsOwnConnectionsKeepTheirTextOrderAndReferences() async throws {
    #expect(try await add("deepwiki", to: "crew-test-target") == .added)

    let text = try #require(sentText("crew-test-target"))
    let sent = jsonMembers(jsonMembers(text[...]).first { $0.key == "\"servers\"" }?.value ?? "")
    let recorded = jsonMembers(jsonMembers(targetConfig[...]).first { $0.key == "\"mcp_servers\"" }?.value ?? "")
    #expect(!text.contains("plaintext-notes"))
    #expect(sent.map(\.key) == ["\"notes\"", "\"deepwiki\""])
    #expect(sent.first?.value == recorded.first?.value)
    #expect(try sentServers("crew-test-target")?["deepwiki"] == .object(["url": .string("https://mcp.deepwiki.com/mcp"), "enabled": .bool(true)]))
}

@Test func aBotWithoutTheKeyIsSkippedAndNothingIsWritten() async throws {
    #expect(try await add("wikikey", to: "crew-test-keyless") == .missingKey)
    #expect(sentText("crew-test-keyless") == nil)
}

@Test func aBotThatHasTheConnectionOrAnotherOfThatNameIsNotWritten() async throws {
    #expect(try await add("deepwiki", to: "crew-test-same") == .alreadyAdded)
    #expect(try await add("deepwiki", to: "crew-test-other") == .differentConnection)
    #expect(sentText("crew-test-same") == nil)
    #expect(sentText("crew-test-other") == nil)
}

@Test func aFreshBotGetsAMapOfJustTheNewConnection() async throws {
    #expect(try await add("deepwiki", to: "crew-test-fresh") == .added)
    #expect(try sentServers("crew-test-fresh") == ["deepwiki": .object(["url": .string("https://mcp.deepwiki.com/mcp"), "enabled": .bool(true)])])
}

@Test func aReadThatIsNotAServerMapWritesNothing() async throws {
    guard case .failed = try await add("deepwiki", to: "crew-test-odd") else { return #expect(Bool(false)) }
    #expect(sentText("crew-test-odd") == nil)
}

@Test func aKeyWrittenIntoTheConfigIsNeverCopied() throws {
    let entry = { (text: String) in try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    let written = [
        #"{"url":"https://a.example/mcp","headers":{"Authorization":"Bearer sk-live"}}"#,
        #"{"url":"https://a.example/mcp","headers":{"X-API-Key":"sk-live"}}"#,
        #"{"command":"npx","args":["server"],"env":{"GITHUB_TOKEN":"ghp_live"}}"#,
        #"{"url":"https://a.example/mcp?api_key=sk-live"}"#,
        #"{"url":"https://user:hunter2@a.example/mcp"}"#,
        #"{"command":"npx","args":["server","--api-key","sk-live"]}"#,
        #"{"command":"npx","args":["server","--token=sk-live"]}"#,
        #"{"url":"https://a.example/mcp","auth":"oauth","oauth":{"client_id":"crew","client_secret":"shh"}}"#,
    ]
    let referenced = [
        #"{"url":"https://a.example/mcp","headers":{"Authorization":"Bearer ${MCP_A_API_KEY}","Notion-Version":"2022-06-28"}}"#,
        #"{"command":"npx","args":["server","--port","8080"],"env":{"GITHUB_TOKEN":"${GITHUB_TOKEN}","NODE_ENV":"production"}}"#,
        #"{"url":"https://a.example/mcp?region=eu"}"#,
    ]
    for text in written {
        #expect(copySkip(for: try entry(text), keys: ["MCP_A_API_KEY", "GITHUB_TOKEN"]) == .writtenKey, "\(text)")
    }
    for text in referenced {
        #expect(copySkip(for: try entry(text), keys: ["MCP_A_API_KEY", "GITHUB_TOKEN"]) == nil, "\(text)")
    }
}
