import Foundation

nonisolated struct Ticket: Decodable, Sendable { let ticket: String }

let env = ProcessInfo.processInfo.environment
let server = try serverURL(from: env["HERMES_URL"] ?? "")
let configuration = URLSessionConfiguration.ephemeral
configuration.timeoutIntervalForRequest = 30
let urlSession = URLSession(configuration: configuration)
_ = try await probe(server, with: urlSession)
_ = try await fetch(hermesRequest("auth/password-login", on: server, json: ["provider": "basic", "username": env["HERMES_USER"] ?? "", "password": env["HERMES_PASSWORD"] ?? ""]), with: urlSession, as: Empty.self)
let gateway = Gateway(server: server, urlSession: urlSession) {
    try await fetch(hermesRequest("api/auth/ws-ticket", on: server, json: [:]), with: urlSession, as: Ticket.self).ticket
}
await gateway.connect()
for _ in 0..<40 where await gateway.status != .connected { try await Task.sleep(for: .milliseconds(250)) }
guard await gateway.status == .connected else { print("not connected"); exit(1) }

if let path = CommandLine.arguments.dropFirst().first {
    let audio = try Data(contentsOf: URL(fileURLWithPath: path))
    var request = hermesRequest("api/audio/transcribe", on: server, json: ["data_url": "data:audio/m4a;base64,\(audio.base64EncodedString())", "mime_type": "audio/m4a"])
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: "crew-test")])
    request.timeoutInterval = 60
    let (body, response) = try await urlSession.data(for: request)
    print("transcribe:", (response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: body, as: UTF8.self))
    exit(0)
}

let store = BotStore(fixture: [], statuses: [:])
await store.reload(gateway)
let original = "crew-test-tmp"
let copy = "crew-test-tmp-2"
guard !store.bots.contains(where: { [original, copy].contains($0.name) }) else { print("probe bots already exist, aborting"); exit(1) }
let before = Set(store.bots.map(\.name))
var failures: [String] = []
func check(_ condition: Bool, _ label: String) {
    print(condition ? "ok  " : "FAIL", label)
    if !condition { failures.append(label) }
}
func bot(_ name: String) -> Bot? { store.bots.first { $0.name == name } }

do {
    try await store.create(NewProfile(name: original, description: "Crew probe bot", soul: "You are a temporary probe bot.", cloneFrom: nil), via: gateway) { meta in
        meta = BotMeta(title: "Crew Probe", shape: "hexagon", color: "#14b8a6", custom: true, imageKind: "shape", expression: "happy")
    }
    check(bot(original) != nil, "create: in roster")
    check(bot(original)?.meta.title == "Crew Probe" && bot(original)?.meta.shape == "hexagon" && bot(original)?.meta.color == "#14b8a6", "create: ui_meta look written")
    check(bot(original)?.meta.extra["created"] != nil, "create: created timestamp")
    check(bot(original)?.description == "Crew probe bot", "create: description")

    if let created = bot(original) {
        let duplicated = try await store.duplicate(created, via: gateway)
        check(duplicated == copy, "duplicate: named \(duplicated)")
        check(bot(copy)?.meta.title == "Crew Probe (copy)" && bot(copy)?.meta.shape == "hexagon", "duplicate: look copied with (copy) title")
    }

    if let created = bot(original) {
        try await store.move(created, to: SectionTag(id: "sec-probe", name: "Crew Probe Section"), via: gateway)
        await store.reload(gateway)
        check(bot(original)?.meta.sectionID == "sec-probe" && bot(original)?.meta.sectionName == "Crew Probe Section", "move: section persisted")
        check(store.sectionTags.contains(SectionTag(id: "sec-probe", name: "Crew Probe Section")), "move: section listed")
    }
    if let filed = bot(original) {
        try await store.move(filed, to: nil, via: gateway)
        await store.reload(gateway)
        check(bot(original)?.meta.sectionID == nil && bot(original)?.meta.title == "Crew Probe", "move: removed from section, title kept")
    }
} catch {
    failures.append("error: \(error)")
    print("FAIL", error)
}

for name in [copy, original] {
    guard let target = bot(name) else { continue }
    do {
        try await store.delete(target, via: gateway, urlSession: urlSession)
        check(bot(name) == nil, "delete: \(name) gone")
    } catch {
        failures.append("delete \(name): \(error)")
        print("FAIL delete", name, error)
    }
}
if let fallback = bot("default") {
    do {
        try await store.delete(fallback, via: gateway, urlSession: urlSession)
        check(false, "delete default refused")
    } catch {
        check(bot("default") != nil, "delete default refused client-side")
    }
}
await store.reload(gateway)
check(Set(store.bots.map(\.name)) == before, "roster back to its original profiles")

print(failures.isEmpty ? "ALL OK" : "FAILURES: \(failures)")
exit(failures.isEmpty ? 0 : 1)
