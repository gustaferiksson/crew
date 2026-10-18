import Foundation
import Testing

nonisolated private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private func decoded<Value: Decodable>(_ path: String, as type: Value.Type) throws -> Value {
    try JSONDecoder().decode(type, from: Data(contentsOf: fixtures.appending(path: path)))
}

private func source(installed: Bool = true, enabled: Bool = true, unlocked: Bool = false) -> VaultSource {
    VaultSource(name: "onepassword", installed: installed, enabled: enabled, unlocked: unlocked)
}

private func status(_ source: VaultSource?, saved: Bool?, listFailed: Bool = false, isDefault: Bool = false, terminalLocal: Bool = false, sourcesFailed: Bool = false) -> OnePasswordStatus? {
    OnePasswordStatus(source: source, sourcesFailed: sourcesFailed, tokenSaved: saved, listFailed: listFailed, isDefault: isDefault, bot: "Vera", terminalLocal: terminalLocal)
}

@Test func realCrewTestCapturesDecode() throws {
    let list = try decoded("vault/real-vault.list.json", as: VaultList.self)
    #expect(list.items.map(\.kind) == ["payment"])
    #expect(Login.list(from: list.items).isEmpty)
    let sources = try decoded("vault/real-vault.sources.json", as: VaultSources.self).sources
    #expect(sources.map(\.name) == ["local", "onepassword", "bitwarden"])
    let onePassword = try #require(sources.first { $0.name == "onepassword" })
    #expect(status(onePassword, saved: false) == OnePasswordStatus(title: "Not set up", footnotes: ["Give Vera its own 1Password vault. The server also needs the 1Password CLI."], action: .connect))
}

@Test func loginsAreOnlyLoginItemsSortedByHostThenUsername() throws {
    let logins = Login.list(from: try decoded("vault/vault.list.json", as: VaultList.self).items)
    #expect(logins.map(\.title) == ["accounts.google.com", "github.com", "Slack app", "www.figma.com +1", "www.sj.se", "www.sj.se"])
    #expect(logins.prefix(4).map(\.detail) == ["ada.lovelace@gmail.com · Verification codes", "ada@example.com", "No username · 1Password", "ada@example.com · 1Password"])
    #expect(logins.suffix(2).allSatisfy { $0.detail.hasPrefix("ada · Saved ") })
    #expect(logins.suffix(2).map(\.created) == [Date(timeIntervalSince1970: 1_785_578_400), Date(timeIntervalSince1970: 1_791_972_000)])
    #expect(logins.map(\.canEdit) == [false, true, false, false, true, true])
    #expect(logins.map(\.isLocal) == [true, true, false, false, true, true])
    #expect(logins.filter(\.isDuplicate).map(\.id) == ["vault_4d5e6f7a8b9c", "vault_3c4d5e6f7a8b"])
}

@Test(arguments: [
    ("ada@example.com", "email"),
    (" Ada.Lovelace ", "username"),
    ("+46 70-123 45 67", "phone"),
    ("(070) 1234567", "phone"),
    ("123456", "username"),
    ("ada+bot", "username"),
])
func identifierTypes(username: String, expected: String) {
    #expect(LoginEntry(website: "example.com", username: username, password: "x").identifierType == expected)
}

@Test func addParamsCarryThePasswordOnlyInTheSecret() throws {
    let params = LoginEntry(website: "https://www.Example.com/login?next=/", username: "  ada@example.com ", password: " pass word ").params(profile: "vera")
    let expected: JSONValue = .object([
        "profile": .string("vera"), "kind": .string("login"), "label": .string("www.example.com"), "origin": .string("https://www.example.com"),
        "secret": .object(["identifier_type": .string("email"), "identifier": .string("ada@example.com"), "password": .string(" pass word ")]),
    ])
    #expect(params == expected)
}

@Test func loginValidation() throws {
    let items = try decoded("vault/vault.list.json", as: VaultList.self).items
    #expect(LoginEntry(website: "not a website", username: "a", password: "x").problem(.website) == "Enter the site's address, such as www.example.com.")
    #expect(LoginEntry(website: "localhost", username: "a", password: "x").problem(.website) != nil)
    #expect(LoginEntry(website: "github.com", username: "  ", password: "x").problem(.username) == "Enter the username or email.")
    #expect(LoginEntry(website: "github.com", username: "a\nb", password: "x").problem(.username) == "Enter the username or email.")
    #expect(LoginEntry(website: "github.com", username: String(repeating: "a", count: 257), password: "x").problem(.username) != nil)
    #expect(LoginEntry(website: "github.com", username: "a", password: "").problem(.password) == "Enter the password.")
    #expect(LoginEntry(website: "github.com", username: "a", password: String(repeating: "x", count: 1025)).problem(.password) == "Enter the password.")
    let duplicate = LoginEntry(website: "github.com", username: "ada@example.com", password: "x")
    #expect(duplicate.problem(.username, existing: items, botTitle: "Vera") == "Vera already has this login for github.com.")
    #expect(duplicate.problem(.username, existing: items, editing: items[0], botTitle: "Vera") == nil)
    #expect(LoginEntry(website: "www.figma.com", username: "ada@example.com", password: "x").problem(.username, existing: items) == nil)
    #expect(LoginEntry(website: "github.com", username: "someone", password: "x").isValid(existing: items))
}

@Test func oneTimeCodeLoginsOfferOnlyRemove() throws {
    let items = try decoded("vault/vault.list.json", as: VaultList.self).items
    let codes = try #require(Login.list(from: items).first { $0.item.hasOtp == true })
    #expect(codes.isLocal && !codes.canEdit)
}

@Test func onePasswordStates() {
    #expect(status(source(installed: false, enabled: false), saved: false)?.action == .connect)
    #expect(status(source(enabled: false), saved: false) == OnePasswordStatus(title: "Turned off for Vera", footnotes: ["1Password is turned off in Vera's Hermes settings."], action: nil))
    #expect(status(source(enabled: false), saved: true)?.action == .disconnect)
    #expect(status(source(), saved: false) == OnePasswordStatus(title: "Not connected", footnotes: ["Give Vera its own 1Password vault, readable with a token only Vera has."], action: .connect))
    #expect(status(source(unlocked: true), saved: false, terminalLocal: true) == OnePasswordStatus(
        title: "Connected through the server's settings", footnotes: ["Change this on the server.", "Bots on this server could read the token and every login in its vault."], look: .connected, action: nil
    ))
    #expect(status(source(installed: false, enabled: false), saved: true) == OnePasswordStatus(title: "Token saved", footnotes: ["Waiting for the 1Password CLI on the server."], action: .disconnect))
    #expect(status(source(unlocked: true), saved: true, listFailed: true) == OnePasswordStatus(title: "1Password didn't answer", footnotes: ["Check that Vera's token is valid and can read its vault."], look: .warning, action: .disconnect))
    #expect(status(source(unlocked: true), saved: true) == OnePasswordStatus(title: "Connected", footnotes: ["Vera's 1Password logins show above. Change them in 1Password."], look: .connected, action: .disconnect))
    #expect(status(nil, saved: nil, sourcesFailed: true)?.action == .retry)
    #expect(status(nil, saved: false)?.action == .retry)
    #expect(status(nil, saved: nil) == nil)
}

@Test func theDefaultBotNeverConnectsFromCrew() {
    for (state, saved) in [(source(installed: false, enabled: false), false), (source(), false), (source(unlocked: true), true)] {
        let main = status(state, saved: saved, isDefault: true)
        #expect(main?.action == nil)
        #expect(main?.footnotes == ["Set up 1Password for the main bot on the server."])
    }
}

@Test(arguments: [
    ("ops_eyJzaWduSW5BZGRyZXNzIjoibXkuMXBhc3N3b3JkLmNvbSJ9", true),
    ("ops_short", false),
    ("eyJzaWduSW5BZGRyZXNzIjoibXkuMXBhc3N3b3JkLmNvbSJ9", false),
    ("ops_eyJzaWduSW5BZGRyZXNz IjoibXkuMXBhc3N3b3JkLmNvbSJ9", false),
])
func serviceAccountTokens(token: String, valid: Bool) {
    #expect(isServiceAccountToken(token) == valid)
}

@Test func envCallsNeverFollowARedirect() async throws {
    RedirectProtocol.followed.withLock { $0 = [] }
    await #expect(throws: HermesError.server(307)) {
        try await envRequest("PUT", profile: "vera", body: ["key": OnePasswordStatus.tokenKey, "value": "ops_x", "profile": "vera"], on: URL(string: "https://redirect.test")!, with: RedirectProtocol.session)
    }
    #expect(RedirectProtocol.followed.withLock { $0 } == ["https://redirect.test/api/env?profile=vera"])
}

@Test func cardVaultAndLeftoverCardsFromCrewPush() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let list = try decoder.decode(ShopList.self, from: Data(contentsOf: fixtures.appending(path: "payments/payments.json")))
    #expect(list.legacyCards == 0)
    let status = PluginStatus(pluginVersion: "0.6.0", installId: "x", apnsConfigured: true, http2: true, devices: 1, features: ["payments", "card", "card_vault"], gate: true)
    #expect(status.hasCardVault && status.supportsCardEntry)
    #expect(!PluginStatus(pluginVersion: "0.5.0", installId: "x", apnsConfigured: true, http2: true, devices: 1, features: ["payments", "card"], gate: true).hasCardVault)
}

@MainActor @Test func fixtureEditAddsThenRemovesTheOldLogin() async throws {
    let items = try decoded("vault/vault.list.json", as: VaultList.self).items
    let vault = BotVault(fixture: "vera", items: items, sources: [], tokenSaved: false)
    let result = await vault.save(LoginEntry(website: "github.com", username: "ada", password: "secret-pass"), replacing: items[0], via: nil)
    #expect(result == .saved(id: "vault_fixture0"))
    #expect(vault.requests == ["vault.add github.com ada", "vault.remove vault_1a2b3c4d5e6f"])
    #expect(!vault.requests.joined().contains("secret-pass"))
    #expect(vault.logins.contains { $0.id == "vault_fixture0" } && !vault.logins.contains { $0.id == "vault_1a2b3c4d5e6f" })
}
