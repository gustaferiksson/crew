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

nonisolated struct ListedSkill: Decodable, Sendable {
    let name: String
    let enabled: Bool?
}

nonisolated struct SkillText: Decodable, Sendable { let content: String }

if CommandLine.arguments.dropFirst().first == "rich" {
    guard crewUISkillVersion(crewUISkill) > 0 else { print("crew-ui.SKILL.md not next to the probe"); exit(1) }
    let store = BotStore(fixture: [], statuses: [:])
    await store.reload(gateway)
    let names = ["crew-test-rich", "crew-test-rich-bare"]
    guard !store.bots.contains(where: { names.contains($0.name) }) else { print("probe bots already exist, aborting"); exit(1) }
    let before = Set(store.bots.map(\.name))
    var failures: [String] = []
    func check(_ condition: Bool, _ label: String) {
        print(condition ? "ok  " : "FAIL", label)
        if !condition { failures.append(label) }
    }
    for name in names {
        do {
            var options = NewBotOptions()
            options.bundledSkills = name == "crew-test-rich"
            let profile = options.profile(name: name, description: nil, soul: nil, cloneFrom: nil)
            try await store.create(profile, via: gateway) { $0 = BotMeta(title: "Crew Rich Probe") }
            let result = await options.apply(to: name, cloneFrom: nil, via: gateway, urlSession: urlSession)
            check(!result.richUIFailed && result.unapplied.isEmpty, "\(name): New Bot steps complete")
            var list = hermesRequest("api/skills", on: server)
            list.url?.append(queryItems: [URLQueryItem(name: "profile", value: name)])
            let listed = try await fetch(list, with: urlSession, as: [ListedSkill].self).first { $0.name == crewUISkillName }
            check(listed != nil && listed?.enabled != false, "\(name): GET /api/skills lists crew-ui enabled (\(String(describing: listed)))")
            let described = try await gateway.call("profiles.describe", ["name": name], as: ProfileDetails.self).skills.first { $0.name == crewUISkillName }
            check(described?.enabled == true, "\(name): profiles.describe shows crew-ui on, so the inspector switch reads on")
            var content = hermesRequest("api/skills/content", on: server)
            content.url?.append(queryItems: [URLQueryItem(name: "name", value: crewUISkillName), URLQueryItem(name: "profile", value: name)])
            let installed = try await fetch(content, with: urlSession, as: SkillText.self).content
            check(installed == crewUISkill, "\(name): installed crew-ui matches the bundled v\(crewUISkillVersion(crewUISkill))")
        } catch {
            failures.append("\(name): \(error)")
            print("FAIL", name, error)
        }
    }
    for name in names {
        guard let target = store.bots.first(where: { $0.name == name }) else { continue }
        do {
            try await store.delete(target, via: gateway, urlSession: urlSession)
            check(!store.bots.contains { $0.name == name }, "delete: \(name) gone")
        } catch {
            failures.append("delete \(name): \(error)")
            print("FAIL delete", name, error)
        }
    }
    await store.reload(gateway)
    check(Set(store.bots.map(\.name)) == before, "roster back to its original profiles")
    print(failures.isEmpty ? "ALL OK" : "FAILURES: \(failures)")
    exit(failures.isEmpty ? 0 : 1)
}

if CommandLine.arguments.dropFirst().first == "model-all" {
    let store = BotStore(fixture: [], statuses: [:])
    await store.reload(gateway)
    let names = ["crew-test-all-1", "crew-test-all-2"]
    guard !store.bots.contains(where: { names.contains($0.name) }) else { print("probe bots already exist, aborting"); exit(1) }
    var failures: [String] = []
    func check(_ condition: Bool, _ label: String) {
        print(condition ? "ok  " : "FAIL", label)
        if !condition { failures.append(label) }
    }
    do {
        for name in names {
            try await store.create(NewProfile(name: name, description: "Crew probe bot", soul: "You are a temporary probe bot.", cloneFrom: nil), via: gateway) { $0 = BotMeta(title: "Crew All Probe") }
        }
        let options = try await gateway.call("model.options", ["profile": names[0]], as: ModelOptions.self)
        let choices = options.providers.flatMap { provider in provider.models.map { ModelChoice(provider: provider.slug, model: $0) } }
        guard let choice = choices.first(where: { $0 != options.current }) else { print("no model to switch to"); exit(1) }
        let created = names.compactMap { name in store.bots.first { $0.name == name } }
        check(created.count == 2, "both throwaways in the roster")
        let missing = Bot(name: "crew-test-all-gone", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta(title: "Gone"), metaRevision: nil)
        let run = ModelForAllBots()
        run.choice = choice
        let apply: ModelForAllBots.Apply = { bot, choice, confirmation in try await changeModel(of: bot, to: choice, confirmation: confirmation, via: gateway) }
        await run.start(on: created + [missing], apply: apply, roster: { created + [missing] })
        if case .confirming = run.phase { await run.confirm(apply: apply, roster: { created + [missing] }) }
        check(run.changed == 2, "two throwaways changed (\(run.changed))")
        check(run.failures.map(\.bot) == ["Gone"], "the missing bot is a per-bot failure (\(run.failures))")
        check(run.remaining.map(\.name) == ["crew-test-all-gone"], "only the failed bot is left for Try Again")
        await store.reload(gateway)
        for name in names {
            check(store.bots.first { $0.name == name }?.model == choice.model, "\(name): profiles.list shows \(choice.model)")
        }
    } catch {
        failures.append("error: \(error)")
        print("FAIL", error)
    }
    for name in names {
        guard let target = store.bots.first(where: { $0.name == name }) else { continue }
        try? await store.delete(target, via: gateway, urlSession: urlSession)
    }
    await store.reload(gateway)
    check(!store.bots.contains { names.contains($0.name) }, "throwaways deleted")
    print(failures.isEmpty ? "ALL OK" : "FAILURES: \(failures)")
    exit(failures.isEmpty ? 0 : 1)
}

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
    if let shown = bot(original) {
        try await store.toggleHidden(shown, via: gateway)
        await store.reload(gateway)
        check(bot(original)?.meta.hidden == true && store.hiddenBots.contains { $0.name == original }, "hide: hermes-bots.hidden persisted, in Hidden")
        check(!store.sections.flatMap(\.bots).contains { $0.name == original } && bot(original)?.meta.title == "Crew Probe", "hide: out of the list, look kept")
    }
    if let hidden = bot(original) {
        try await store.toggleHidden(hidden, via: gateway)
        await store.reload(gateway)
        check(bot(original)?.meta.hidden == false && store.sections.flatMap(\.bots).contains { $0.name == original }, "unhide: back in the list")
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
