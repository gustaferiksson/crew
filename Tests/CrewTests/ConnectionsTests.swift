import Foundation
import Synchronization
import Testing

nonisolated private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/mcp")

nonisolated private func fixture(_ name: String) -> Data {
    (try? Data(contentsOf: fixtures.appending(path: "\(name).v0.22.5.json"))) ?? Data()
}

private func decoded<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: fixture(name))
}

nonisolated private final class MCPServerStub: URLProtocol {
    static let requests = Mutex<[String]>([])
    static let polls = Mutex(0)
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MCPServerStub.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let path = url.path()
        MCPServerStub.requests.withLock { $0.append("\(request.httpMethod ?? "GET") \(path)?\(url.query() ?? "")") }
        let body: Data
        if path.hasSuffix("/servers") {
            body = fixture("servers")
        } else if path.hasSuffix("/deepwiki/test") {
            body = fixture("test-ok")
        } else if path.hasSuffix("/linear/test") {
            body = fixture("test-oauth")
        } else if path.hasSuffix("/test") {
            body = fixture("test-fail")
        } else if path.hasSuffix("/auth") {
            body = fixture("auth")
        } else {
            let poll = MCPServerStub.polls.withLock { count in
                count += 1
                return count
            }
            body = Data(#"{"flow_id":"FLOW","server_name":"linear","status":"\#(poll < 2 ? "authorization_required" : "approved")","authorization_url":null,"error":null,"tools":[{"name":"list_issues","description":""},{"name":"create_issue","description":""}]}"#.utf8)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Test func realServerCapturesDecode() throws {
    let servers = try decoded("servers", as: MCPServerList.self).servers
    #expect(servers.map(\.name) == ["crew-probe", "deepwiki", "linear"])
    #expect(servers.map(\.auth) == [nil, nil, "oauth"])
    #expect(servers.map(\.enabled) == [true, false, true])
    #expect(try decoded("test-ok", as: MCPTestResult.self).tools.count == 3)
    let catalog = try decoded("catalog", as: MCPCatalog.self).entries
    #expect(catalog.map(\.name) == ["asana", "deepwiki", "linear"])
    #expect(catalog.first?.requiredEnv.map(\.isSecret) == [false, true])
    #expect(catalog.map(\.authType) == ["oauth", "none", "oauth"])
    let flow = try decoded("auth", as: MCPOAuthFlow.self)
    #expect(flow.status == "authorization_required")
    #expect(flow.authorizationUrl?.contains("redirect_uri=https%3A%2F%2Fhermes.gustaf.dev%2Fapi%2Fmcp%2Foauth%2Fcallback%2Flinear") == true)
}

@Test func statusFollowsTheTestResult() throws {
    let servers = try decoded("servers", as: MCPServerList.self).servers
    let probe = servers[0], deepwiki = servers[1], linear = servers[2]
    var enabledDeepwiki = deepwiki
    enabledDeepwiki.enabled = true
    let ok = try decoded("test-ok", as: MCPTestResult.self)
    let oauth = try decoded("test-oauth", as: MCPTestResult.self)
    let failed = try decoded("test-fail", as: MCPTestResult.self)
    #expect(ConnectionStatus(server: deepwiki, test: ok, isSigningIn: false) == .off)
    #expect(ConnectionStatus(server: enabledDeepwiki, test: ok, isSigningIn: false) == .connected(tools: 3))
    #expect(ConnectionStatus(server: enabledDeepwiki, test: nil, isSigningIn: false) == .checking)
    #expect(ConnectionStatus(server: linear, test: oauth, isSigningIn: false) == .needsSignIn(oauth.error))
    #expect(ConnectionStatus(server: linear, test: oauth, isSigningIn: true) == .signingIn)
    #expect(ConnectionStatus(server: probe, test: failed, isSigningIn: false) == .failed(failed.error ?? ""))
}

@Test(arguments: [("servers", "GET", false), ("servers/linear/enabled", "PUT", true), ("servers/linear", "DELETE", false), ("catalog/install", "POST", true)])
func everyRequestIsScopedToTheBot(path: String, method: String, hasBody: Bool) throws {
    let server = try #require(URL(string: "https://hermes.invalid"))
    let request = mcpRequest(path, profile: "crew-test", method: method, body: hasBody ? ["name": .string("linear")] : nil, on: server)
    #expect(request.url?.absoluteString == "https://hermes.invalid/api/mcp/\(path)?profile=crew-test")
    #expect(request.httpMethod == method)
    guard hasBody else { return }
    let body = try JSONDecoder().decode([String: JSONValue].self, from: try #require(request.httpBody))
    #expect(body["profile"] == .string("crew-test"))
}

@Test func customConnectionBuildsWhatHermesAccepts() {
    var entry = CustomConnection(name: " Docs ", kind: .url, url: "https://docs.example.com/mcp")
    #expect(entry.body == ["name": .string("Docs"), "url": .string("https://docs.example.com/mcp"), "auth": .string("none")])
    entry.auth = .apiKey
    #expect(entry.body == nil)
    entry.token = " sk-123 "
    #expect(entry.body?["auth"] == .string("header"))
    #expect(entry.body?["bearer_token"] == .string("sk-123"))
    entry.auth = .signIn
    #expect(entry.body?["auth"] == .string("oauth"))
    #expect(entry.body?["bearer_token"] == nil)
    entry.url = "docs.example.com"
    #expect(entry.problem == "Enter the server's address, starting with https://.")

    var command = CustomConnection(name: "fs", kind: .command, url: "https://ignored.example.com", auth: .apiKey, token: "x", command: "npx", arguments: "-y\n@modelcontextprotocol/server-filesystem\n\n/data", environment: "ROOT=/data\nTOKEN=a=b")
    #expect(command.body == [
        "name": .string("fs"), "command": .string("npx"),
        "args": .array([.string("-y"), .string("@modelcontextprotocol/server-filesystem"), .string("/data")]),
        "env": .object(["ROOT": .string("/data"), "TOKEN": .string("a=b")]),
    ])
    command.environment = "ROOT /data"
    #expect(command.body == nil)
    #expect(command.problem == "Write each variable as NAME=value: ROOT /data")
    #expect(CustomConnection(kind: .command, command: "npx").problem == "Enter a name.")
}

@Test func loadTestsEnabledServersAndSignInEndsConnected() async throws {
    let server = try #require(URL(string: "https://hermes.invalid"))
    let store = BotConnections(profile: "crew-test")
    await store.load(on: server, with: MCPServerStub.session)
    let servers = try #require(store.servers)
    #expect(servers.map { store.status(of: $0) } == [.failed("[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: self-signed certificate (_ssl.c:1082)"), .off, .needsSignIn(try decoded("test-oauth", as: MCPTestResult.self).error)])

    let opened = Mutex<[URL]>([])
    await store.signIn("linear", on: server, with: MCPServerStub.session) { url in opened.withLock { $0.append(url) } }
    #expect(opened.withLock { $0.map(\.host) } == ["mcp.linear.app"])
    #expect(store.status(of: servers[2]) == .connected(tools: 2))
    #expect(store.failures.isEmpty)

    let requests = MCPServerStub.requests.withLock { $0 }
    #expect(requests.allSatisfy { $0.hasSuffix("?profile=crew-test") })
    #expect(!requests.contains { $0.contains("deepwiki/test") })
    #expect(requests.filter { $0.hasPrefix("GET /api/mcp/oauth/flows/FLOW") }.count == 2)
}
