import Foundation

nonisolated struct VaultItem: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let label: String
    let origin: String?
    let createdAt: String
    var identifier: String?
    var identifierType: String?
    var hasOtp: Bool?
    var allowedOrigins: [String]?
    let backend: String

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, origin, identifier, backend
        case createdAt = "created_at"
        case identifierType = "identifier_type"
        case hasOtp = "has_otp"
        case allowedOrigins = "allowed_origins"
    }
}

nonisolated struct VaultList: Decodable, Sendable {
    let items: [VaultItem]
}

nonisolated struct VaultSource: Decodable, Equatable, Sendable {
    let name: String
    let installed: Bool
    let enabled: Bool
    let unlocked: Bool
}

nonisolated struct VaultSources: Decodable, Sendable {
    let sources: [VaultSource]
}

nonisolated struct Login: Equatable, Identifiable, Sendable {
    let item: VaultItem
    let isDuplicate: Bool

    var id: String { item.id }

    var isLocal: Bool { item.backend == "local" }

    var host: String? {
        item.origin.flatMap { URL(string: $0) }.flatMap { $0.scheme == "https" ? $0.host() : nil }
    }

    var title: String {
        guard let host else { return item.label }
        let extra = Set(item.allowedOrigins ?? []).subtracting([item.origin ?? ""]).count
        return extra > 0 ? "\(host) +\(extra)" : host
    }

    var created: Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(item.createdAt)) ?? (try? Date.ISO8601FormatStyle().parse(item.createdAt))
    }

    var account: String {
        item.identifier.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "No username")
    }

    var tags: [String] {
        var tags: [String] = []
        if !isLocal { tags.append(String(localized: "1Password")) }
        if item.hasOtp == true { tags.append(String(localized: "Verification codes")) }
        if isDuplicate, let created { tags.append(String(localized: "Saved \(created.formatted(.dateTime.day().month(.abbreviated)))")) }
        return tags
    }

    var canEdit: Bool { isLocal && item.hasOtp != true }

    static func list(from items: [VaultItem]) -> [Login] {
        let logins = items.filter { $0.kind == "login" }
        let local = logins.filter { $0.backend == "local" }
        return logins
            .map { item in
                Login(item: item, isDuplicate: item.backend == "local" && local.filter { $0.origin == item.origin && $0.identifier == item.identifier }.count > 1)
            }
            .sorted { ($0.title.lowercased(), ($0.item.identifier ?? "").lowercased(), $0.item.createdAt) < ($1.title.lowercased(), ($1.item.identifier ?? "").lowercased(), $1.item.createdAt) }
    }
}

nonisolated enum LoginField: CaseIterable, Hashable, Sendable {
    case website, username, password
}

nonisolated struct LoginEntry: Sendable {
    let website: String
    let username: String
    let password: String

    var host: String? { shopHost(from: website) }

    var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }

    var identifierType: String {
        if trimmedUsername.contains("@") { return "email" }
        let allowed = CharacterSet(charactersIn: "0123456789 +-()")
        let isPhone = trimmedUsername.unicodeScalars.allSatisfy(allowed.contains) && trimmedUsername.filter(\.isNumber).count >= 7
        return isPhone ? "phone" : "username"
    }

    func problem(_ field: LoginField, existing: [VaultItem] = [], editing: VaultItem? = nil, botTitle: String = "") -> String? {
        if field == .website {
            return host == nil ? String(localized: "Enter the site's address, such as www.example.com.") : nil
        }
        if field == .username {
            guard !trimmedUsername.isEmpty, trimmedUsername.count <= 256, !trimmedUsername.contains(where: \.isNewline) else {
                return String(localized: "Enter the username or email.")
            }
            guard let host else { return nil }
            let taken = existing.contains { $0.kind == "login" && $0.backend == "local" && $0.id != editing?.id && $0.origin == "https://\(host)" && $0.identifier == trimmedUsername }
            return taken ? String(localized: "\(botTitle) already has this login for \(host).") : nil
        }
        return password.isEmpty || password.count > 1024 ? String(localized: "Enter the password.") : nil
    }

    func isValid(existing: [VaultItem] = [], editing: VaultItem? = nil) -> Bool {
        LoginField.allCases.allSatisfy { problem($0, existing: existing, editing: editing) == nil }
    }

    func canSave(block: SecretBlock?, existing: [VaultItem], editing: VaultItem?) -> Bool {
        block == nil && isValid(existing: existing, editing: editing)
    }

    func params(profile: String) -> JSONValue {
        let host = host ?? ""
        return .object([
            "profile": .string(profile), "kind": .string("login"), "label": .string(host), "origin": .string("https://\(host)"),
            "secret": .object(["identifier_type": .string(identifierType), "identifier": .string(trimmedUsername), "password": .string(password)]),
        ])
    }
}

nonisolated enum SecretBlock: Equatable, Sendable {
    case http, offline

    init?(server: URL?, isOnline: Bool) {
        if server?.scheme?.lowercased() != "https" {
            self = .http
        } else if !isOnline {
            self = .offline
        } else {
            return nil
        }
    }
}

nonisolated func canConnect(token: String, block: SecretBlock?) -> Bool {
    block == nil && isServiceAccountToken(token)
}

nonisolated func isServiceAccountToken(_ token: String) -> Bool {
    token.hasPrefix("ops_") && (20...4096).contains(token.count) && !token.contains(where: \.isWhitespace)
}

nonisolated struct OnePasswordStatus: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case connect, disconnect, retry
    }

    enum Look: Equatable, Sendable {
        case plain, connected, warning
    }

    let title: String
    let footnotes: [String]
    let look: Look
    let action: Action?

    static let tokenKey = "OP_SERVICE_ACCOUNT_TOKEN"

    init(title: String, footnotes: [String], look: Look = .plain, action: Action?) {
        self.title = title
        self.footnotes = footnotes
        self.look = look
        self.action = action
    }

    init?(source: VaultSource?, sourcesFailed: Bool, envFailed: Bool = false, tokenSaved: Bool?, listFailed: Bool, isDefault: Bool, bot: String, terminalLocal: Bool) {
        if sourcesFailed || envFailed || (source == nil && tokenSaved != nil) {
            self.init(title: String(localized: "Couldn't check 1Password."), footnotes: [], action: .retry)
            return
        }
        guard let source, let tokenSaved else { return nil }
        let readable = String(localized: "Bots on this server could read the token and every login in its vault.")
        let base: OnePasswordStatus
        if !tokenSaved && source.unlocked {
            base = OnePasswordStatus(title: String(localized: "Connected through the server's settings"), footnotes: [String(localized: "Change this on the server.")] + (terminalLocal ? [readable] : []), look: .connected, action: nil)
        } else if !source.installed {
            base = tokenSaved
                ? OnePasswordStatus(title: String(localized: "Token saved"), footnotes: [String(localized: "Waiting for the 1Password CLI on the server.")], action: .disconnect)
                : OnePasswordStatus(title: String(localized: "Not set up"), footnotes: [String(localized: "Give \(bot) its own 1Password vault. The server also needs the 1Password CLI.")], action: .connect)
        } else if !source.enabled {
            base = OnePasswordStatus(title: String(localized: "Turned off for \(bot)"), footnotes: [String(localized: "1Password is turned off in \(bot)'s Hermes settings.")], action: tokenSaved ? .disconnect : nil)
        } else if !tokenSaved {
            base = OnePasswordStatus(title: String(localized: "Not connected"), footnotes: [String(localized: "Give \(bot) its own 1Password vault, readable with a token only \(bot) has.")], action: .connect)
        } else if !source.unlocked {
            base = OnePasswordStatus(title: String(localized: "Token saved"), footnotes: [String(localized: "Hermes hasn't read the token yet.")], action: .disconnect)
        } else if listFailed {
            base = OnePasswordStatus(title: String(localized: "1Password didn't answer"), footnotes: [String(localized: "Check that \(bot)'s token is valid and can read its vault.")], look: .warning, action: .disconnect)
        } else {
            base = OnePasswordStatus(title: String(localized: "Connected"), footnotes: [String(localized: "\(bot)'s 1Password logins show above. Change them in 1Password.")] + (terminalLocal ? [readable] : []), look: .connected, action: .disconnect)
        }
        guard isDefault, base.action != nil else {
            self = base
            return
        }
        self.init(title: base.title, footnotes: [String(localized: "Set up 1Password for the main bot on the server.")] + base.footnotes.filter { $0 == readable }, look: base.look, action: nil)
    }
}

struct VaultLink {
    let gateway: Gateway
    let server: URL
    let urlSession: URLSession
}

nonisolated private struct AddedItem: Decodable, Sendable {
    let id: String
}

nonisolated private struct RemovedItem: Decodable, Sendable {
    let removed: Bool
}

nonisolated func envRequest(_ method: String, profile: String, body: [String: String]? = nil, on server: URL, with urlSession: URLSession) async throws -> Data {
    var request = hermesRequest("api/env", on: server, json: body)
    request.httpMethod = method
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile)])
    let (data, response) = try await urlSession.data(for: request, delegate: RefusingRedirects())
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else { throw HermesError.server(status, detail: nil) }
    return data
}

nonisolated private struct EnvToken: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        let isSet: Bool?

        private enum CodingKeys: String, CodingKey {
            case isSet = "is_set"
        }
    }

    let token: Row?

    private enum CodingKeys: String, CodingKey {
        case token = "OP_SERVICE_ACCOUNT_TOKEN"
    }
}

nonisolated private struct TerminalConfig: Decodable, Sendable {
    struct Terminal: Decodable, Sendable {
        let backend: String?
    }

    let terminal: Terminal?
}

@Observable
final class BotVault {
    let profile: String
    private(set) var items: [VaultItem]?
    private(set) var listFailed = false
    private(set) var sources: [VaultSource]?
    private(set) var sourcesFailed = false
    private(set) var tokenSaved: Bool?
    private(set) var envFailed = false
    private(set) var terminalBackend: String?
    private(set) var requests: [String] = []
    private let isFixture: Bool

    init(profile: String) {
        self.profile = profile
        isFixture = false
    }

    init(fixture profile: String, items: [VaultItem]?, listFailed: Bool = false, sources: [VaultSource]?, sourcesFailed: Bool = false, tokenSaved: Bool?, terminalBackend: String? = "local") {
        self.profile = profile
        self.items = items
        self.listFailed = listFailed
        self.sources = sources
        self.sourcesFailed = sourcesFailed
        self.tokenSaved = tokenSaved
        self.terminalBackend = terminalBackend
        isFixture = true
    }

    var logins: [Login] {
        Login.list(from: items ?? [])
    }

    var onePassword: VaultSource? {
        sources?.first { $0.name == "onepassword" }
    }

    var isTerminalLocal: Bool {
        (terminalBackend ?? "local") == "local"
    }

    func load(_ link: VaultLink) async {
        guard !isFixture else { return }
        let profile = profile
        var configRequest = hermesRequest("api/config", on: link.server)
        configRequest.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile)])
        async let list = try? await link.gateway.call("vault.list", ["profile": profile], as: VaultList.self)
        async let sourceList = try? await link.gateway.call("vault.sources", ["profile": profile], as: VaultSources.self)
        async let env = try? await envRequest("GET", profile: profile, on: link.server, with: link.urlSession)
        async let config = try? await fetch(configRequest, with: link.urlSession, as: TerminalConfig.self)
        let (listed, sourced, envRows, configured) = await (list, sourceList, env, config)
        if let listed { items = listed.items }
        listFailed = listed == nil
        if let sourced { sources = sourced.sources }
        sourcesFailed = sourced == nil
        let token = envRows.flatMap { try? JSONDecoder().decode(EnvToken.self, from: $0) }
        if let token { tokenSaved = token.token?.isSet == true }
        envFailed = token == nil
        terminalBackend = configured?.terminal?.backend ?? "local"
    }

    func save(_ entry: LoginEntry, replacing old: VaultItem?, via link: VaultLink?) async -> String? {
        let params = entry.params(profile: profile)
        if isFixture {
            let id = "vault_fixture\(requests.count)"
            requests.append("vault.add \(entry.host ?? "") \(entry.trimmedUsername)")
            items = (items ?? []).filter { $0.id != old?.id } + [VaultItem(id: id, kind: "login", label: entry.host ?? "", origin: "https://\(entry.host ?? "")", createdAt: "2026-10-18T09:41:00+00:00", identifier: entry.trimmedUsername, identifierType: entry.identifierType, backend: "local")]
            if let old { requests.append("vault.remove \(old.id)") }
            return id
        }
        guard let link else { return nil }
        let added: String
        do {
            added = try await link.gateway.call("vault.add", params, as: AddedItem.self).id
        } catch {
            await load(link)
            return nil
        }
        guard let old else {
            await load(link)
            return added
        }
        _ = await remove(old, via: link)
        return added
    }

    func remove(_ item: VaultItem, via link: VaultLink?) async -> Bool {
        if isFixture {
            requests.append("vault.remove \(item.id)")
            items?.removeAll { $0.id == item.id }
            return true
        }
        guard let link else { return false }
        do {
            _ = try await link.gateway.call("vault.remove", ["profile": profile, "id": item.id], as: RemovedItem.self)
            await load(link)
            return true
        } catch {
            await load(link)
            return false
        }
    }

    func connect(token: String, via link: VaultLink?) async -> Bool {
        if isFixture {
            requests.append("env.put \(OnePasswordStatus.tokenKey)")
            tokenSaved = true
            return true
        }
        guard let link else { return false }
        do {
            _ = try await envRequest("PUT", profile: profile, body: ["key": OnePasswordStatus.tokenKey, "value": token, "profile": profile], on: link.server, with: link.urlSession)
            await load(link)
            return true
        } catch {
            await load(link)
            return false
        }
    }

    func disconnect(via link: VaultLink?) async -> Bool {
        if isFixture {
            requests.append("env.delete \(OnePasswordStatus.tokenKey)")
            tokenSaved = false
            return true
        }
        guard let link else { return false }
        do {
            _ = try await envRequest("DELETE", profile: profile, body: ["key": OnePasswordStatus.tokenKey, "profile": profile], on: link.server, with: link.urlSession)
        } catch HermesError.server(404, _) {
        } catch {
            await load(link)
            return false
        }
        await load(link)
        return true
    }
}
