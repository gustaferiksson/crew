import Foundation

nonisolated struct MCPServer: Decodable, Equatable, Identifiable, Sendable {
    let name: String
    let transport: String
    let url: String?
    let command: String?
    let args: [String]
    let auth: String?
    var enabled: Bool
    let source: String
    let plugin: String?

    var id: String { name }

    var address: String {
        url ?? ([command ?? ""] + args).joined(separator: " ")
    }
}

nonisolated struct MCPServerList: Decodable, Sendable {
    let servers: [MCPServer]
}

nonisolated struct MCPTool: Decodable, Equatable, Sendable {
    let name: String
}

nonisolated struct MCPTestResult: Decodable, Equatable, Sendable {
    let ok: Bool
    let error: String?
    let tools: [MCPTool]
}

nonisolated struct MCPEnvSpec: Decodable, Equatable, Sendable {
    let name: String
    let prompt: String
    let required: Bool

    var isSecret: Bool {
        ["KEY", "TOKEN", "SECRET", "PASSWORD"].contains { name.uppercased().contains($0) }
    }
}

nonisolated struct MCPCatalogEntry: Decodable, Equatable, Identifiable, Sendable {
    let name: String
    let description: String
    let transport: String
    let authType: String
    let requiredEnv: [MCPEnvSpec]
    let command: String?
    let args: [String]
    let url: String?
    let postInstall: String
    let installed: Bool

    var id: String { name }
}

nonisolated struct MCPCatalog: Decodable, Sendable {
    let entries: [MCPCatalogEntry]
}

nonisolated struct MCPOAuthFlow: Decodable, Sendable {
    let flowId: String
    let status: String
    let authorizationUrl: String?
    let error: String?
    let tools: [MCPTool]?
}

nonisolated enum ConnectionStatus: Equatable, Sendable {
    case off, checking, connected(tools: Int), needsSignIn(String?), signingIn, failed(String)

    init(server: MCPServer, test: MCPTestResult?, isSigningIn: Bool) {
        if isSigningIn {
            self = .signingIn
        } else if !server.enabled {
            self = .off
        } else if let test, test.ok {
            self = .connected(tools: test.tools.count)
        } else if let test, server.auth == "oauth" {
            self = .needsSignIn(test.error)
        } else if let test {
            self = .failed(test.error ?? String(localized: "The server didn't answer."))
        } else {
            self = .checking
        }
    }
}

nonisolated func connectionTitle(_ name: String) -> String {
    name.replacing("-", with: " ").replacing("_", with: " ").capitalized
}

nonisolated func mcpRequest(_ path: String, profile: String, method: String = "GET", body: [String: JSONValue]? = nil, on server: URL) -> URLRequest {
    var request = hermesRequest("api/mcp/\(path)", on: server)
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile)])
    request.httpMethod = method
    guard var body else { return request }
    body["profile"] = .string(profile)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(body)
    return request
}

nonisolated struct CustomConnection: Equatable, Sendable {
    enum Kind: Hashable, Sendable {
        case url, command
    }

    enum Auth: Hashable, Sendable {
        case none, apiKey, signIn
    }

    var name = ""
    var kind = Kind.url
    var url = ""
    var auth = Auth.none
    var token = ""
    var command = ""
    var arguments = ""
    var environment = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var lines: (arguments: [String], environment: [String]) {
        let split = { (text: String) in text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return (split(arguments), split(environment))
    }

    var problem: String? {
        if trimmedName.isEmpty { return String(localized: "Enter a name.") }
        if kind == .url {
            let parsed = URL(string: url.trimmingCharacters(in: .whitespaces))
            guard let scheme = parsed?.scheme?.lowercased(), ["https", "http"].contains(scheme), parsed?.host()?.isEmpty == false else {
                return String(localized: "Enter the server's address, starting with https://.")
            }
            return auth == .apiKey && token.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Enter the API key.") : nil
        }
        if command.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Enter the command that starts the server.") }
        let badLine = lines.environment.first { line in
            let key = line.split(separator: "=", maxSplits: 1).first ?? ""
            return !line.contains("=") || key.isEmpty || key.contains(" ")
        }
        return badLine.map { String(localized: "Write each variable as NAME=value: \($0)") }
    }

    var body: [String: JSONValue]? {
        guard problem == nil else { return nil }
        if kind == .url {
            var body: [String: JSONValue] = ["name": .string(trimmedName), "url": .string(url.trimmingCharacters(in: .whitespaces))]
            body["auth"] = .string([.none: "none", .apiKey: "header", .signIn: "oauth"][auth] ?? "none")
            if auth == .apiKey { body["bearer_token"] = .string(token.trimmingCharacters(in: .whitespaces)) }
            return body
        }
        let environment = lines.environment.map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
        return [
            "name": .string(trimmedName),
            "command": .string(command.trimmingCharacters(in: .whitespaces)),
            "args": .array(lines.arguments.map(JSONValue.string)),
            "env": .object(Dictionary(environment.map { ($0[0], JSONValue.string($0.count > 1 ? $0[1] : "")) }) { _, last in last }),
        ]
    }
}

@Observable
final class BotConnections {
    let profile: String
    private(set) var servers: [MCPServer]?
    private(set) var loadFailed = false
    private(set) var tests: [MCPServer.ID: MCPTestResult] = [:]
    private(set) var busy: Set<MCPServer.ID> = []
    private(set) var signingIn: [MCPServer.ID: String] = [:]
    var failures: [MCPServer.ID: String] = [:]
    private(set) var catalog: [MCPCatalogEntry]?
    private(set) var catalogFailed = false
    private(set) var requests: [String] = []
    private let isFixture: Bool

    init(profile: String) {
        self.profile = profile
        isFixture = false
    }

    init(fixture profile: String, servers: [MCPServer]?, loadFailed: Bool = false, tests: [MCPServer.ID: MCPTestResult] = [:], signingIn: [MCPServer.ID: String] = [:], catalog: [MCPCatalogEntry]? = nil) {
        self.profile = profile
        self.servers = servers
        self.loadFailed = loadFailed
        self.tests = tests
        self.signingIn = signingIn
        self.catalog = catalog
        isFixture = true
    }

    func status(of server: MCPServer) -> ConnectionStatus {
        ConnectionStatus(server: server, test: tests[server.id], isSigningIn: signingIn[server.id] != nil)
    }

    func load(on server: URL, with urlSession: URLSession) async {
        guard !isFixture else { return }
        do {
            let list = try await fetch(mcpRequest("servers", profile: profile, on: server), with: urlSession, as: MCPServerList.self).servers
            servers = list
            loadFailed = false
            tests = tests.filter { name, _ in list.contains { $0.name == name } }
            await withTaskGroup { group in
                for item in list where item.enabled && tests[item.id] == nil && !busy.contains(item.id) {
                    group.addTask { await self.test(item.name, on: server, with: urlSession) }
                }
            }
        } catch {
            loadFailed = servers == nil
        }
    }

    func loadCatalog(on server: URL, with urlSession: URLSession) async {
        guard !isFixture else { return }
        do {
            catalog = try await fetch(mcpRequest("catalog", profile: profile, on: server), with: urlSession, as: MCPCatalog.self).entries
            catalogFailed = false
        } catch {
            catalogFailed = catalog == nil
        }
    }

    func test(_ name: String, on server: URL, with urlSession: URLSession) async {
        if isFixture { return requests.append("test \(name)") }
        busy.insert(name)
        defer { busy.remove(name) }
        do {
            tests[name] = try await fetch(mcpRequest("servers/\(name)/test", profile: profile, method: "POST", on: server), with: urlSession, as: MCPTestResult.self)
        } catch {
            tests[name] = MCPTestResult(ok: false, error: error.localizedDescription, tools: [])
        }
    }

    func setEnabled(_ enabled: Bool, for name: String, on server: URL, with urlSession: URLSession) async {
        guard let index = servers?.firstIndex(where: { $0.name == name }) else { return }
        servers?[index].enabled = enabled
        failures[name] = nil
        if isFixture { return requests.append("enabled \(name) \(enabled)") }
        busy.insert(name)
        do {
            _ = try await fetch(mcpRequest("servers/\(name)/enabled", profile: profile, method: "PUT", body: ["enabled": .bool(enabled)], on: server), with: urlSession, as: JSONValue.self)
            busy.remove(name)
            guard enabled else { return }
            tests[name] = nil
            await test(name, on: server, with: urlSession)
        } catch {
            busy.remove(name)
            failures[name] = error.localizedDescription
            await load(on: server, with: urlSession)
        }
    }

    func remove(_ name: String, on server: URL, with urlSession: URLSession) async {
        failures[name] = nil
        if isFixture {
            requests.append("remove \(name)")
            servers?.removeAll { $0.name == name }
            return
        }
        busy.insert(name)
        defer { busy.remove(name) }
        do {
            _ = try await fetch(mcpRequest("servers/\(name)", profile: profile, method: "DELETE", on: server), with: urlSession, as: JSONValue.self)
        } catch HermesError.server(404, _) {
        } catch {
            failures[name] = error.localizedDescription
            return
        }
        servers?.removeAll { $0.name == name }
        tests[name] = nil
    }

    func add(_ body: [String: JSONValue], catalog: Bool, on server: URL, with urlSession: URLSession) async throws {
        if isFixture { return requests.append("add") }
        _ = try await fetch(mcpRequest(catalog ? "catalog/install" : "servers", profile: profile, method: "POST", body: body, on: server), with: urlSession, as: JSONValue.self)
        await load(on: server, with: urlSession)
        await loadCatalog(on: server, with: urlSession)
    }

    func signIn(_ name: String, on server: URL, with urlSession: URLSession, browse: @escaping (URL) async throws -> Void) async {
        if isFixture { return requests.append("sign in \(name)") }
        guard !busy.contains(name), signingIn[name] == nil else { return }
        failures[name] = nil
        busy.insert(name)
        let flow: MCPOAuthFlow
        do {
            flow = try await fetch(mcpRequest("servers/\(name)/auth", profile: profile, method: "POST", on: server), with: urlSession, as: MCPOAuthFlow.self)
            busy.remove(name)
        } catch {
            busy.remove(name)
            failures[name] = error.localizedDescription
            return
        }
        guard flow.status == "authorization_required", let url = flow.authorizationUrl.flatMap(URL.init(string:)) else {
            failures[name] = flow.error ?? String(localized: "Hermes couldn't start the sign-in.")
            return
        }
        signingIn[name] = flow.flowId
        defer { signingIn[name] = nil }
        let browser = Task { try? await browse(url) }
        defer { browser.cancel() }
        for _ in 0..<240 {
            guard (try? await Task.sleep(for: .milliseconds(1500))) != nil else { return }
            let polled: MCPOAuthFlow
            do {
                polled = try await fetch(mcpRequest("oauth/flows/\(flow.flowId)", profile: profile, on: server), with: urlSession, as: MCPOAuthFlow.self)
            } catch HermesError.server(404, _) {
                break
            } catch {
                continue
            }
            if polled.status == "approved" {
                tests[name] = MCPTestResult(ok: true, error: nil, tools: polled.tools ?? [])
                return
            }
            if polled.status == "error" {
                if polled.error != "Cancelled by user" { failures[name] = polled.error }
                return
            }
        }
        failures[name] = String(localized: "The sign-in expired. Try again.")
    }

    func cancelSignIn(_ name: String, on server: URL, with urlSession: URLSession) async {
        guard let flowID = signingIn[name] else { return }
        if isFixture { return requests.append("cancel \(name)") }
        _ = try? await fetch(mcpRequest("oauth/flows/\(flowID)", profile: profile, method: "DELETE", on: server), with: urlSession, as: JSONValue.self)
    }
}
