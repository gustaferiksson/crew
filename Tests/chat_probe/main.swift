import Foundation
import CoreGraphics
import CoreText
import ImageIO

nonisolated struct Ticket: Decodable, Sendable { let ticket: String }
nonisolated struct BotRoster: Decodable, Sendable { let profiles: [Bot] }

let env = ProcessInfo.processInfo.environment
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let phases = Set(CommandLine.arguments.dropFirst(2))
let server = try serverURL(from: env["HERMES_URL"] ?? "")
let configuration = URLSessionConfiguration.ephemeral
configuration.timeoutIntervalForRequest = 30
let urlSession = URLSession(configuration: configuration)
_ = try await probe(server, with: urlSession)
_ = try await fetch(hermesRequest("auth/password-login", on: server, json: ["provider": "basic", "username": env["HERMES_USER"] ?? "", "password": env["HERMES_PASSWORD"] ?? ""]), with: urlSession, as: Empty.self)
let gateway = Gateway(server: server, urlSession: urlSession) {
    try await fetch(hermesRequest("api/auth/ws-ticket", on: server, json: [:]), with: urlSession, as: Ticket.self).ticket
}

var eventLog: FileHandle?
var recordedAt = Date.now
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
Task {
    for await event in gateway.events() {
        var object: [String: JSONValue] = ["type": .string(event.type), "payload": event.payload ?? .null]
        if let id = event.sessionID { object["session_id"] = .string(id.rawValue) }
        if let seq = event.seq { object["seq"] = .number(Double(seq)) }
        object["at"] = .number((Date.now.timeIntervalSince(recordedAt) * 1000).rounded() / 1000)
        if let data = try? encoder.encode(JSONValue.object(object)) { eventLog?.write(data + Data("\n".utf8)) }
    }
}
Task {
    for await request in gateway.serverRequests() {
        print("SRQ", request.method, request.id)
        if let data = try? encoder.encode(JSONValue.object(["id": .string(request.id), "method": .string(request.method), "params": request.params])) { eventLog?.write(Data("SRQ ".utf8) + data + Data("\n".utf8)) }
    }
}

func record(_ name: String) {
    let url = outDir.appending(path: "\(name).jsonl")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    recordedAt = .now
    eventLog = try? FileHandle(forWritingTo: url)
}

Task { for await status in gateway.statuses() { print("GATEWAY", status, Date.now.formatted(date: .omitted, time: .standard)) } }
await gateway.connect()
for _ in 0..<40 where await gateway.status != .connected { try await Task.sleep(for: .milliseconds(250)) }
print("status", await gateway.status)

func crewTest() async throws -> Bot {
    let bots = try await gateway.call("profiles.list", ["include_sessions": true], as: BotRoster.self).profiles
    guard let bot = bots.first(where: { $0.name == "crew-test" }) else { print("no crew-test"); exit(1) }
    return bot
}

func summary(_ transcript: Transcript) -> [String] {
    transcript.turns.map { turn in
        let work = turn.work.map { item -> String in
            if case .thinking(let text) = item.kind { return "think(\(text.prefix(30)))" }
            if case .note(let text) = item.kind { return "note(\(text.prefix(30)))" }
            if case .tool(let call) = item.kind { return "\(call.name)[\(call.status.rawValue)](\(call.subject.prefix(30)))\(item.duration.map { String(format: "%.1fs", $0) } ?? "-")" }
            return "?"
        }
        let worked = (turn.finishedAt ?? turn.startedAt).timeIntervalSince(turn.startedAt)
        return "[\(turn.status.rawValue)]\(turn.isSteer ? " steer" : "") \(turn.prompt?.text.prefix(40) ?? "<no prompt>") | \(work.joined(separator: ", "))\(turn.answer.map { " | answer \($0.prefix(50))" } ?? "") | worked \(Int(worked))s | \(turn.reply.prefix(70).replacingOccurrences(of: "\n", with: " "))\(turn.failure.map { " !\($0)" } ?? "")"
    }
}

func attached(_ bot: Bot) async throws -> ChatSession {
    let chat = ChatSession(bot: bot, gateway: gateway, urlSession: urlSession)
    Task { await chat.run() }
    for _ in 0..<80 {
        try await Task.sleep(for: .milliseconds(250))
        if chat.failure != nil || !chat.transcript.turns.isEmpty { break }
    }
    try await Task.sleep(for: .seconds(1))
    if let failure = chat.failure { print("FAILURE", failure) }
    return chat
}

func waitIdle(_ chat: ChatSession, timeout: Int = 300, until: (ChatSession) -> Bool = { !$0.isRunning && $0.transcript.waiting.isEmpty }) async throws {
    for _ in 0..<(timeout * 4) {
        try await Task.sleep(for: .milliseconds(250))
        if until(chat) { return }
    }
    print("TIMEOUT")
}

func show(_ label: String, _ chat: ChatSession) {
    print("== \(label): \(chat.transcript.turns.count) turns, todos \(chat.todos.count), failure \(chat.failure ?? "-")")
    for line in summary(chat.transcript).suffix(4) { print("  ", line) }
}

if phases.contains("fresh") {
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/scenarios/new-bot-chat").standardized
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user"), (name, "crew-test-peer")].filter { $0.0.count > 2 }
    func save(_ file: String, _ value: JSONValue) throws {
        let text = scrubs.reduce(String(decoding: try pretty.encode(value), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }.replacing(/\/opt\/data\/[^\s"'\\]*/, with: "/opt/hermes/data")
        try Data((text + "\n").utf8).write(to: folder.appending(path: "\(file).json"))
        print("RECORDED \(file).json")
    }
    func roster() async throws -> (raw: JSONValue, bot: Bot?) {
        let raw = try await gateway.call("profiles.list", ["include_sessions": true], as: JSONValue.self)
        guard case .object(let object) = raw, case .array(let profiles) = object["profiles"] else { return (.object(["profiles": .array([])]), nil) }
        let kept = profiles.filter { if case .object(let profile) = $0, case .string(name) = profile["name"] { true } else { false } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (.object(["profiles": .array(kept)]), try decoder.decode([Bot].self, from: encoder.encode(JSONValue.array(kept))).first)
    }
    func live(of bot: Bot?) async throws -> (raw: JSONValue, statuses: [String]) {
        let keys = [bot?.canonicalSession?.id.rawValue, bot?.canonicalSession?.resolvedID.rawValue].compactMap(\.self)
        let raw = try await gateway.call("session.active_list", [String: String](), as: JSONValue.self)
        guard case .object(let object) = raw, case .array(let sessions) = object["sessions"] else { return (.object(["sessions": .array([])]), []) }
        let kept = sessions.filter { if case .object(let session) = $0, case .string(let key) = session["session_key"] { keys.contains(key) } else { false } }
        let statuses = kept.compactMap { if case .object(let session) = $0, case .string(let status) = session["status"] { status } else { nil } }
        return (.object(["sessions": .array(kept)]), statuses)
    }
    func describe(_ key: String) async throws -> String {
        let listed = try await gateway.call("session.list", ["profile": .string(name), "include_hidden": .bool(true), "limit": .number(50)] as [String: JSONValue], as: JSONValue.self)
        var visible = URLRequest(url: URL(string: "\(server.absoluteString)/api/sessions?profile=\(name)&order=recent&limit=50")!)
        visible.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await urlSession.data(for: visible)
        guard case .object(let object) = listed, case .array(let rows) = object["sessions"],
              case .object(let row)? = rows.first(where: { if case .object(let row) = $0, case .string(key) = row["id"] { true } else { false } })
        else { return "no row" }
        let title = if case .string(let title) = row["title"], !title.isEmpty { title } else { "untitled" }
        return "\(title), \(String(decoding: data, as: UTF8.self).contains(key) ? "visible" : "hidden")"
    }

    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    do {
        try await store.create(NewProfile(name: name, description: "Crew scenario bot", soul: nil, cloneFrom: nil), via: gateway) { meta in
            meta = BotMeta(title: "Crew Fresh", shape: "hexagon", color: "#14b8a6", custom: true, imageKind: "shape", expression: "happy")
        }

        let dropped = try await connectedPeer()
        let minted = try await dropped.call("session.create", ["profile": .string(name), "title": .string("Bot Chat"), "hidden": .bool(true), "follow_profile_config": .bool(true)] as [String: JSONValue], as: JSONValue.self)
        guard case .object(let created) = minted, case .string(let mintedKey) = created["stored_session_id"] else { throw HermesError.invalidResponse }
        await dropped.disconnect()
        try await Task.sleep(for: .seconds(30))
        _ = try await gateway.call("session.resume", ["session_id": .string(mintedKey), "profile": .string(name), "omit_messages": .bool(true)] as [String: JSONValue], as: JSONValue.self)
        print("WITHOUT session.title, reaped then resumed:", try await describe(mintedKey))

        let before = try await roster()
        try save("profiles.before", before.raw)
        guard let fresh = before.bot, fresh.canonicalSession == nil else { throw HermesError.invalidResponse }
        let leaving = try await connectedPeer()
        let first = ChatSession(bot: fresh, gateway: leaving, urlSession: urlSession)
        let firstRun = Task { await first.run() }
        try await Task.sleep(for: .seconds(4))
        firstRun.cancel()
        await leaving.disconnect()
        try await Task.sleep(for: .seconds(30))
        let opened = try await roster()
        try save("profiles.opened", opened.raw)
        guard let titled = opened.bot, let session = titled.canonicalSession else { throw HermesError.invalidResponse }
        print("WITH session.title, reaped:", try await describe(session.id.rawValue))

        let chat = try await attached(titled)
        chat.send("Use your terminal tool to run: sleep 6 && echo fresh-ok. Then reply with just the output.", mode: .send)
        var duringSaved = false
        let started = Date.now
        while Date.now.timeIntervalSince(started) < 180, !duringSaved || chat.isRunning {
            try await Task.sleep(for: .milliseconds(250))
            let current = try await roster()
            let active = try await live(of: current.bot)
            if !duringSaved, active.statuses.contains("working") {
                try save("profiles.during", current.raw)
                try save("active_list.during", active.raw)
                duringSaved = true
            }
        }
        if !duringSaved { print("WARNING: never saw the fresh Bot Chat working") }
        try await Task.sleep(for: .seconds(5))
        let after = try await roster()
        try save("profiles.after", after.raw)
        try save("active_list.after", try await live(of: after.bot).raw)
        if let session = after.bot?.canonicalSession {
            let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: name, on: server, limit: 20))
            guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { throw HermesError.invalidResponse }
            let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "display_kind"]
            try save("crew-test-peer.preview", .array(messages.map { row in if case .object(let object) = row { .object(object.filter { keys.contains($0.key) }) } else { row } }))
        }
    } catch {
        print("FRESH FAILED", error)
    }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try await store.delete(bot, via: gateway, urlSession: urlSession) }
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("cold-open") {
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/scenarios/cold-open").standardized
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user"), (name, "crew-test-peer")].filter { $0.0.count > 2 }
    func save(_ file: String, _ value: JSONValue) throws {
        let text = scrubs.reduce(String(decoding: try pretty.encode(value), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }.replacing(/\/opt\/data\/[^\s"'\\]*/, with: "/opt/hermes/data")
        try Data((text + "\n").utf8).write(to: folder.appending(path: "\(file).json"))
        print("RECORDED \(file).json")
    }
    func roster() async throws -> (raw: JSONValue, bot: Bot?) {
        let raw = try await gateway.call("profiles.list", ["include_sessions": true], as: JSONValue.self)
        guard case .object(let object) = raw, case .array(let profiles) = object["profiles"] else { return (.object(["profiles": .array([])]), nil) }
        let kept = profiles.filter { if case .object(let profile) = $0, case .string(name) = profile["name"] { true } else { false } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (.object(["profiles": .array(kept)]), try decoder.decode([Bot].self, from: encoder.encode(JSONValue.array(kept))).first)
    }
    func live(of key: String) async throws -> (raw: JSONValue, statuses: [String]) {
        let raw = try await gateway.call("session.active_list", [String: String](), as: JSONValue.self)
        guard case .object(let object) = raw, case .array(let sessions) = object["sessions"] else { return (.object(["sessions": .array([])]), []) }
        let kept = sessions.filter { if case .object(let session) = $0, case .string(key) = session["session_key"] { true } else { false } }
        let statuses = kept.compactMap { if case .object(let session) = $0, case .string(let status) = session["status"] { status } else { nil } }
        return (.object(["sessions": .array(kept)]), statuses)
    }
    func rows(of key: String) async throws -> [JSONValue] {
        let (data, _) = try await urlSession.data(for: historyRequest(of: StoredSessionID(rawValue: key), profile: name, on: server, limit: 500))
        guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { return [] }
        let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "display_kind"]
        return messages.map { row in if case .object(let object) = row { .object(object.filter { keys.contains($0.key) }) } else { row } }
    }

    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    do {
        try await store.create(NewProfile(name: name, description: "Crew scenario bot", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Cold" }
        let terminal = try await connectedPeer()
        let minted = try await terminal.call("session.create", ["profile": .string(name), "source": .string("cli")] as [String: JSONValue], as: JSONValue.self)
        guard case .object(let created) = minted, case .string(let runtime) = created["session_id"], case .string(let key) = created["stored_session_id"] else { throw HermesError.invalidResponse }
        _ = try await terminal.call("session.title", ["session_id": runtime, "title": "Bot Chat"], as: JSONValue.self)
        guard let made = try await roster().bot, made.canonicalSession?.id.rawValue == key else { throw HermesError.invalidResponse }
        let cli = ChatSession(bot: made, gateway: terminal, urlSession: urlSession)
        let cliRun = Task { await cli.run() }
        try await Task.sleep(for: .seconds(3))
        cli.send("Reply with just: earlier", mode: .send)
        try await waitIdle(cli, timeout: 120)
        cliRun.cancel()
        await terminal.disconnect()
        let earlier = try await rows(of: key).count
        try await Task.sleep(for: .seconds(30))

        let before = try await roster()
        try save("profiles.before", before.raw)
        guard let reaped = before.bot else { throw HermesError.invalidResponse }
        let crew = ChatSession(bot: reaped, gateway: gateway, urlSession: urlSession)
        Task { await crew.run() }
        for _ in 0..<40 where crew.transcript.turns.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
        crew.send("Hi", mode: .send)
        let sent = Date.now
        var timeline: [String] = []
        var saved: Set<String> = []
        while Date.now.timeIntervalSince(sent) < 120, crew.isRunning || Date.now.timeIntervalSince(sent) < 2 {
            let active = try await live(of: key)
            let status = active.statuses.first ?? "none"
            if timeline.last?.hasPrefix(status) != true { timeline.append(String(format: "%@ from +%.1fs", status, Date.now.timeIntervalSince(sent))) }
            if crew.isRunning, ["starting", "working"].contains(status), !saved.contains(status) {
                saved.insert(status)
                try save("profiles.\(status)", try await roster().raw)
                try save("active_list.\(status)", active.raw)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        print("COLD-OPEN live status while Crew's chat ran:", timeline.joined(separator: ", "))
        try await Task.sleep(for: .seconds(3))
        try save("profiles.after", try await roster().raw)
        try save("active_list.after", try await live(of: key).raw)
        let after = try await rows(of: key)
        try save("crew-test-peer.history", .array(after))
        print("COLD-OPEN rows before open \(earlier), after Hi \(after.count)")
    } catch {
        print("COLD-OPEN FAILED", error)
    }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try await store.delete(bot, via: gateway, urlSession: urlSession) }
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("first") {
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    do {
        try await store.create(NewProfile(name: name, description: "Crew scenario bot", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew First" }
        await store.reload(gateway)
        guard let fresh = store.bots.first(where: { $0.name == name }) else { throw HermesError.invalidResponse }
        record("first-turn")
        let chat = ChatSession(bot: fresh, gateway: gateway, urlSession: urlSession)
        Task { await chat.run() }
        try await Task.sleep(for: .seconds(3))
        chat.send("Reply with just: hi", mode: .send)
        var seen: [String] = []
        let started = Date.now
        while Date.now.timeIntervalSince(started) < 120, seen.isEmpty || chat.isRunning || !chat.transcript.waiting.isEmpty {
            if let line = chat.statusLine, seen.last != line { seen.append(line); print("FIRST statusLine:", line) }
            if chat.isRunning, seen.isEmpty { seen.append("") }
            try await Task.sleep(for: .milliseconds(100))
        }
        show("first live", chat)
        await store.reload(gateway)
        if let titled = store.bots.first(where: { $0.name == name }) { show("first reload", try await attached(titled)) }
    } catch {
        print("FIRST FAILED", error)
    }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try await store.delete(bot, via: gateway, urlSession: urlSession) }
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("routine") {
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/scenarios/routine-delivery").standardized
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user"), (env["HERMES_PASSWORD"] ?? "", "***"), (name, "crew-test-peer")].filter { $0.0.count > 2 }
    func save(_ file: String, _ value: JSONValue) throws {
        let text = scrubs.reduce(String(decoding: try pretty.encode(value), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }.replacing(/\/opt\/data\/[^\s"'\\]*/, with: "/opt/hermes/data").replacing(/uid:[0-9]+/, with: "uid:user")
        try Data((text + "\n").utf8).write(to: folder.appending(path: "\(file).json"))
        print("RECORDED \(file).json")
    }
    func roster() async throws -> (raw: JSONValue, bot: Bot?) {
        let raw = try await gateway.call("profiles.list", ["include_sessions": true], as: JSONValue.self)
        guard case .object(let object) = raw, case .array(let profiles) = object["profiles"] else { return (.object(["profiles": .array([])]), nil) }
        let kept = profiles.filter { if case .object(let profile) = $0, case .string(name) = profile["name"] { true } else { false } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (.object(["profiles": .array(kept)]), try decoder.decode([Bot].self, from: encoder.encode(JSONValue.array(kept))).first)
    }
    func rows(of bot: Bot?, limit: Int) async throws -> [JSONValue] {
        guard let session = bot?.canonicalSession else { return [] }
        let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: name, on: server, limit: limit))
        guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { return [] }
        let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "reasoning", "reasoning_content", "display_kind"]
        return messages.map { row in if case .object(let object) = row { .object(object.filter { keys.contains($0.key) }) } else { row } }
    }
    func field(_ row: JSONValue, _ key: String) -> String? {
        if case .object(let object) = row, case .string(let value) = object[key] { value } else { nil }
    }
    func replied(_ window: [JSONValue]) -> Bool? {
        guard let brief = window.lastIndex(where: { field($0, "display_kind") == "internal_notification" }) else { return nil }
        return window[(brief + 1)...].contains { field($0, "role") == "assistant" && !(field($0, "content") ?? "").isEmpty }
    }

    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    var jobID: String?
    do {
        try await store.create(NewProfile(name: name, description: "Crew scenario bot", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Routine" }
        try save("profiles.before", try await roster().raw)
        let added = try await gateway.call("cron.manage", [
            "action": .string("add"), "profile": .string(name), "name": .string("[bot:\(name)] Morning brief"), "schedule": .string("every 1440m"),
            "prompt": .string("Reply with exactly this text and nothing else: Two new emails. Anna asks to move Friday's lunch to 12:30. The Telia invoice of 412 kr is due on October 31."),
            "deliver": .string("bot-chat"),
        ] as [String: JSONValue], as: JSONValue.self)
        guard case .object(let job) = added, case .string(let id) = job["job_id"] else { print("ADD FAILED", added); throw HermesError.invalidResponse }
        jobID = id
        print("routine added", id)
        var trigger = hermesRequest("api/cron/jobs/\(id)/trigger", on: server, json: [:])
        trigger.url?.append(queryItems: [URLQueryItem(name: "profile", value: name)])
        _ = try await fetch(trigger, with: urlSession, as: JSONValue.self)
        let started = Date.now
        print("triggered")
        var duringSaved = false
        var quietSince: Date?
        var last = ""
        while Date.now.timeIntervalSince(started) < 600 {
            try await Task.sleep(for: .seconds(1))
            let current = try await roster()
            let window = try await rows(of: current.bot, limit: 20)
            let state = "session \(current.bot?.canonicalSession?.resolvedID.rawValue ?? "none"): " + window.map { "\(field($0, "role") ?? "?")/\(field($0, "display_kind") ?? "-")" }.joined(separator: " ")
            if state != last { print(String(format: "+%.0fs ", Date.now.timeIntervalSince(started)) + state) }
            last = state
            let done = replied(window)
            if !duringSaved, done == false {
                try save("profiles.during", current.raw)
                try save("crew-test-peer.preview.during", .array(window))
                duringSaved = true
            }
            quietSince = done == true ? quietSince ?? .now : nil
            if let quietSince, Date.now.timeIntervalSince(quietSince) > 15 { break }
        }
        let after = try await roster()
        try save("profiles.after", after.raw)
        try save("crew-test-peer.history", .array(try await rows(of: after.bot, limit: 500)))
        try save("crew-test-peer.preview", .array(try await rows(of: after.bot, limit: 20)))
        let listed = try await gateway.call("session.list", ["profile": .string(name), "include_hidden": .bool(true), "limit": .number(20)] as [String: JSONValue], as: JSONValue.self)
        if case .object(let object) = listed, case .array(let sessions) = object["sessions"] {
            for session in sessions { print("SESSION", field(session, "id") ?? "-", field(session, "title") ?? "-", field(session, "source") ?? "-") }
        }
        print("canonical", after.bot?.canonicalSession?.id.rawValue ?? "none")
    } catch {
        print("ROUTINE FAILED", error)
    }
    if let jobID {
        let removed = try? await gateway.call("cron.manage", ["action": .string("remove"), "profile": .string(name), "name": .string(jobID)] as [String: JSONValue], as: JSONValue.self)
        print("routine removed:", removed.map { "\($0)" } ?? "failed")
    }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try await store.delete(bot, via: gateway, urlSession: urlSession) }
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("slash") {
    let catalog = try await gateway.call("commands.catalog", ["profile": "crew-test"], as: JSONValue.self)
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let file = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/commands.catalog.v0.22.5.json").standardized
    try (pretty.encode(catalog) + Data("\n".utf8)).write(to: file)
    print("RECORDED", file.lastPathComponent, try JSONDecoder().decode(SlashCatalog.self, from: pretty.encode(catalog)).commands.count, "commands")
    exit(0)
}

if phases.contains("other") {
    nonisolated struct Row: Decodable, Sendable { let id: StoredSessionID; let title: String?; let source: String? }
    nonisolated struct Page: Decodable, Sendable { let sessions: [Row] }
    func otherRows() async throws -> [Row] {
        var request = hermesRequest("api/sessions", on: server)
        request.url?.append(queryItems: [URLQueryItem(name: "profile", value: "crew-test"), URLQueryItem(name: "order", value: "recent"), URLQueryItem(name: "limit", value: "50")])
        let bot = try await crewTest()
        return try await fetch(request, with: urlSession, as: Page.self).sessions.filter { $0.title != "Bot Chat" && $0.id != bot.canonicalSession?.id && $0.id != bot.canonicalSession?.resolvedID }
    }
    if try await otherRows().isEmpty {
        let seeded = try await gateway.call("session.create", ["profile": "crew-test", "title": "Crew other conversation probe"], as: JSONValue.self)
        guard case .object(let fields) = seeded, case .string(let runtime) = fields["session_id"] else { print("no runtime"); exit(1) }
        _ = try await gateway.call("prompt.submit", ["session_id": runtime, "text": "Reply with exactly: seeded"], as: JSONValue.self)
        try await Task.sleep(for: .seconds(20))
    }
    let bot = try await crewTest()
    let botChatBefore = try await history(of: bot.canonicalSession!.id, profile: "crew-test", on: server, with: urlSession).count
    let before = try await otherRows()
    let target = before[0]
    print("other", target.id.rawValue, target.title ?? "-", target.source ?? "-")
    record("other-conversation")
    let chat = ChatSession(bot: bot, resuming: target.id, gateway: gateway, urlSession: urlSession)
    Task { await chat.run() }
    try await waitIdle(chat, timeout: 20) { !$0.transcript.turns.isEmpty || $0.failure != nil }
    show("other attach", chat)
    chat.send("Reply with exactly: other-ok", mode: .send)
    try await waitIdle(chat)
    show("other reply", chat)
    let rows = try await history(of: target.id, profile: "crew-test", on: server, with: urlSession)
    print("other history has reply", rows.contains { $0.content?.contains("other-ok") == true })
    print("bot chat rows unchanged", try await history(of: bot.canonicalSession!.id, profile: "crew-test", on: server, with: urlSession).count == botChatBefore)
    let after = try await otherRows().first { $0.id == target.id }
    print("other row after", after?.title ?? "missing", after?.source ?? "-")
    exit(0)
}

let bot = try await crewTest()
print("canonical", bot.canonicalSession?.id.rawValue ?? "nil")
let chat = try await attached(bot)
show("attach", chat)

if phases.contains("tool") {
    record("tool-turn")
    chat.send("Use your terminal tool to run ls in your current working directory, then tell me in one short sentence how many entries there are.", mode: .send)
    try await waitIdle(chat)
    show("tool live", chat)
    let live = summary(chat.transcript).last ?? ""
    let reloaded = try await attached(try await crewTest())
    show("tool reload", reloaded)
    let fromHistory = summary(reloaded.transcript).last ?? ""
    print("LIVE    ", live)
    print("HISTORY ", fromHistory)
    print("turn counts", chat.transcript.turns.count, reloaded.transcript.turns.count)
}

if phases.contains("think") {
    record("think-turn")
    chat.send("Think it through, then use your terminal tool to count the files in your current directory, and answer in one sentence.", mode: .send)
    try await waitIdle(chat)
    show("think live", chat)
}

if phases.contains("interrupt") {
    record("interrupt-turn")
    chat.send("Use the terminal to run: sleep 40 && echo done. Then tell me the output.", mode: .send)
    try await waitIdle(chat, timeout: 60) { chat in
        chat.transcript.turns.last?.work.contains { if case .tool(let call) = $0.kind { call.status == .running } else { false } } ?? false
    }
    chat.send("this should be queued then dropped by stop", mode: .queue)
    print("queue before stop", chat.transcript.waiting.count)
    chat.stop()
    try await waitIdle(chat, timeout: 60)
    show("interrupt", chat)
}

if phases.contains("queue") {
    record("queue-turn")
    chat.send("Use the terminal to run: sleep 5 && echo first. Reply with just the output.", mode: .send)
    try await Task.sleep(for: .seconds(2))
    chat.send("Reply with exactly: queued-ok", mode: .queue)
    print("queued", chat.transcript.waiting.compactMap(\.prompt?.text))
    try await waitIdle(chat)
    show("queue", chat)
}

if phases.contains("steer") {
    record("steer-turn")
    chat.send("Use the terminal to run: sleep 6 && echo step-one. Then reply with the output.", mode: .send)
    try await waitIdle(chat, timeout: 60) { chat in
        chat.transcript.turns.last?.work.contains { if case .tool = $0.kind { true } else { false } } ?? false
    }
    chat.send("Also include the word STEERED in your final reply.", mode: .steer)
    try await waitIdle(chat)
    show("steer", chat)
}

if phases.contains("steer-rows"), let session = try await crewTest().canonicalSession {
    let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: "crew-test", on: server, limit: 7))
    let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "reasoning", "reasoning_content", "display_kind", "display_content", "display_commentary", "display_reasoning"]
    if case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] {
        let kept = messages.map { row in if case .object(let object) = row { JSONValue.object(object.filter { keys.contains($0.key) }) } else { row } }
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try pretty.encode(JSONValue.array(kept)).write(to: outDir.appending(path: "steer-rows.json"))
        print("ROWS", outDir.appending(path: "steer-rows.json").path)
    }
}

if phases.contains("steer-answer") {
    record("steer-answer-turn")
    chat.send("Use the terminal to run: sleep 8 && echo step-one. Then run: echo step-two. Then reply with both outputs.", mode: .send)
    try await waitIdle(chat, timeout: 60) { chat in
        chat.transcript.turns.last?.work.contains { if case .tool = $0.kind { true } else { false } } ?? false
    }
    chat.send("Before your next tool call, reply to this note in one short sentence, then carry on.", mode: .steer)
    try await waitIdle(chat)
    show("steer-answer live", chat)
    let reloaded = try await attached(try await crewTest())
    show("steer-answer history", reloaded)
    guard let session = try await crewTest().canonicalSession else { exit(1) }
    let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: "crew-test", on: server, limit: 12))
    guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { exit(1) }
    let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "reasoning", "reasoning_content", "display_kind", "display_content", "finish_reason"]
    for row in messages { if case .object(let object) = row { print("ROW KEYS", object.filter { if case .null = $0.value { false } else { true } }.keys.sorted()) } }
    let kept = messages.map { row in if case .object(let object) = row { JSONValue.object(object.filter { keys.contains($0.key) }) } else { row } }
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try pretty.encode(JSONValue.array(kept)).write(to: outDir.appending(path: "steer-answer.history.json"))
    print("history rows written to", outDir.appending(path: "steer-answer.history.json").path)
}

if phases.contains("clarify") {
    record("clarify-turn")
    chat.send("Use your clarify tool to ask me one question: which colour I prefer, with the choices red and blue. Then reply with my answer.", mode: .send)
    try await waitIdle(chat, timeout: 120) { $0.request != nil || !$0.isRunning }
    if case .question(let question) = chat.request {
        print("QUESTION", question.questions.map { "\($0.id): \($0.text) \($0.choices)" })
        chat.answer(question.id, with: [question.questions[0].id: question.questions[0].choices.last ?? "blue"])
    } else {
        print("no question card", String(describing: chat.request))
    }
    try await waitIdle(chat)
    show("clarify", chat)
}

if phases.contains("reconnect") {
    record("reconnect-turn")
    chat.send("Use the terminal to run: sleep 8 && echo reconnected. Then reply with the output.", mode: .send)
    try await waitIdle(chat, timeout: 60) { chat in
        chat.transcript.turns.last?.work.contains { if case .tool = $0.kind { true } else { false } } ?? false
    }
    print("forcing reconnect mid-turn")
    await gateway.reconnect()
    try await waitIdle(chat)
    show("reconnect live", chat)
    let reloaded = try await attached(try await crewTest())
    show("reconnect reload", reloaded)
    var adopted = reloaded.transcript
    adopted.adoptIDs(from: chat.transcript)
    print("reload adopts live ids", adopted.turns.map(\.id) == chat.transcript.turns.map(\.id), adopted.turns.last?.work.map(\.id) == chat.transcript.turns.last?.work.map(\.id))
    var windowed = reloaded.transcript
    windowed.turns.removeFirst(3)
    windowed.adoptIDs(from: chat.transcript)
    print("windowed reload adopts live ids", windowed.turns.map(\.id) == Array(chat.transcript.turns.map(\.id).dropFirst(3)))
    let before = chat.transcript.turns.map(\.id)
    await gateway.reconnect()
    try await Task.sleep(for: .seconds(5))
    print("idle reconnect keeps ids", before == chat.transcript.turns.map(\.id))
}

if phases.contains("attach") {
    record("attach-turn")
    let side = 320
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.setFillColor(CGColor(red: 0.95, green: 0.1, blue: 0.1, alpha: 1))
    context.fillEllipse(in: CGRect(x: 80, y: 80, width: 160, height: 160))
    let png = NSMutableData()
    let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    let pdf = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 300, height: 200)
    let pdfContext = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &box, nil)!
    pdfContext.beginPDFPage(nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Quarterly report: revenue was 42 million kronor.", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 10, nil)]))
    pdfContext.textPosition = CGPoint(x: 10, y: 100)
    CTLineDraw(line, pdfContext)
    pdfContext.endPDFPage()
    pdfContext.closePDF()
    let image = try Attachment(data: png as Data, name: "probe.png")
    let text = try Attachment(data: Data("Crew attachment probe\nThe secret word is PELICAN.\n".utf8), name: "probe notes.txt")
    let document = try Attachment(data: pdf as Data, name: "report.pdf")
    print("prepared", image.kind, image.data?.count ?? 0, text.kind, document.kind, document.mimeType)
    chat.send("Describe the attached image in one short sentence, then tell me the secret word from the attached text file.", attachments: [image, text], mode: .send)
    try await waitIdle(chat)
    show("attach image+text", chat)
    chat.send("What revenue does the attached PDF report? Answer in one sentence.", attachments: [document], mode: .send)
    try await waitIdle(chat)
    show("attach pdf", chat)
    chat.send("", attachments: [image], mode: .send)
    try await waitIdle(chat)
    show("attach image only", chat)
    let reloaded = try await attached(try await crewTest())
    show("attach reload", reloaded)
    for turn in reloaded.transcript.turns.suffix(3) {
        print("PROMPT", turn.prompt?.text.debugDescription ?? "nil", "REPLY", turn.reply.debugDescription)
        for attachment in turn.prompt?.attachments ?? [] {
            let bytes = (try? await reloaded.download(attachment).count).map(String.init) ?? "download failed"
            print("   ", attachment.kind, attachment.name, attachment.path ?? "-", bytes)
        }
    }
}

func connectedPeer() async throws -> Gateway {
    let peer = Gateway(server: server, urlSession: urlSession) {
        try await fetch(hermesRequest("api/auth/ws-ticket", on: server, json: [:]), with: urlSession, as: Ticket.self).ticket
    }
    await peer.connect()
    for _ in 0..<40 where await peer.status != .connected { try await Task.sleep(for: .milliseconds(250)) }
    return peer
}

if phases.contains("peer") {
    record("peer-turn")
    let peerGateway = try await connectedPeer()
    let peer = ChatSession(bot: bot, gateway: peerGateway, urlSession: urlSession)
    Task { await peer.run() }
    try await Task.sleep(for: .seconds(3))
    show("peer attach", peer)
    let started = Date.now
    var lastSeen = ""
    chat.send("Use the terminal to run: sleep 3 && echo peer-sync. Then reply with just the output.", mode: .send)
    for _ in 0..<480 {
        try await Task.sleep(for: .milliseconds(250))
        let line = summary(peer.transcript).last ?? ""
        if line != lastSeen {
            print(String(format: "  B +%.2fs", Date.now.timeIntervalSince(started)), line)
            lastSeen = line
        }
        if !chat.isRunning && !peer.isRunning && Date.now.timeIntervalSince(started) > 3 { break }
    }
    show("A", chat)
    show("B", peer)
    print("SAME", summary(chat.transcript).last == summary(peer.transcript).last)
    await peerGateway.disconnect()
}

if phases.contains("late") {
    record("late-turn")
    chat.send("Use the terminal to run: sleep 4 && echo late-ok. Then reply with just the output.", mode: .send)
    var lates: [ChatSession] = []
    while chat.isRunning {
        let late = ChatSession(bot: bot, gateway: gateway, urlSession: urlSession)
        Task { await late.run() }
        lates.append(late)
        try await Task.sleep(for: .milliseconds(300))
    }
    try await Task.sleep(for: .seconds(5))
    let stuck = lates.filter(\.isRunning)
    print("LATE \(lates.count) sessions attached mid-turn, \(stuck.count) still streaming after message.complete")
    if let first = stuck.first { show("stuck", first) }
    print(stuck.isEmpty && !chat.isRunning ? "STOP OK" : "STOP STALE")
}

if phases.contains("sync") {
    let peerGateway = try await connectedPeer()
    let storeA = BotStore(fixture: [], statuses: [:])
    let storeB = BotStore(fixture: [], statuses: [:])
    Task { await storeA.run(gateway, urlSession: urlSession) }
    Task { await storeB.run(peerGateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    func measure(_ label: String, _ change: () async throws -> Void, until done: (Bot) -> Bool) async throws {
        let started = Date.now
        try await change()
        for _ in 0..<80 {
            if let bot = storeB.bots.first(where: { $0.name == "crew-test" }), done(bot) {
                return print(String(format: "SYNC %@ seen on B after %.2fs", label, Date.now.timeIntervalSince(started)))
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("SYNC \(label) NOT seen on B")
    }
    guard let original = storeA.bots.first(where: { $0.name == "crew-test" }) else { print("no crew-test in store"); exit(1) }
    let wasPinned = original.meta.pinned == true
    try await measure("pin", { try await storeA.togglePin(original, via: gateway) }, until: { ($0.meta.pinned == true) != wasPinned })
    try await measure("unpin", { try await storeA.togglePin(storeA.bots.first { $0.name == "crew-test" }!, via: gateway) }, until: { ($0.meta.pinned == true) == wasPinned })
    let section = SectionTag(id: "sec-probe", name: "Probe")
    try await measure("section", { try await storeA.move(storeA.bots.first { $0.name == "crew-test" }!, to: section, via: gateway) }, until: { $0.meta.sectionID == "sec-probe" })
    let restore = original.meta.sectionID.flatMap { id in original.meta.sectionName.map { SectionTag(id: id, name: $0) } }
    try await measure("section restore", { try await storeA.move(storeA.bots.first { $0.name == "crew-test" }!, to: restore, via: gateway) }, until: { $0.meta.sectionID == original.meta.sectionID })
    await peerGateway.disconnect()
}

if phases.contains("read") {
    let peerGateway = try await connectedPeer()
    let storeA = BotStore(fixture: [], statuses: [:])
    let storeB = BotStore(fixture: [], statuses: [:])
    Task { await storeA.run(gateway, urlSession: urlSession) }
    Task { await storeB.run(peerGateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    let started = Date.now
    func crew(_ store: BotStore) -> Bot { store.bots.first { $0.name == "crew-test" }! }
    func status(_ store: BotStore) -> String { store.statuses["crew-test"].map { "\($0)" } ?? "idle" }
    func position(_ value: ReadPosition?) -> String { value.map { "\($0.session.suffix(6))#\($0.messages)" } ?? "-" }
    func report(_ label: String) {
        for (name, store) in [("A", storeA), ("B", storeB)] {
            let bot = crew(store)
            print(String(format: "READ +%.1fs %@ %@: %@ at %@ marker %@ rev %d", Date.now.timeIntervalSince(started), label, name, status(store), position(bot.canonicalSession?.position), position(bot.readPosition), bot.readRevision ?? 0))
        }
    }
    func wait(_ label: String, timeout: Double = 15, until done: () -> Bool) async throws {
        let begun = Date.now
        while Date.now.timeIntervalSince(begun) < timeout {
            if done() { return print(String(format: "READ %@ after %.2fs", label, Date.now.timeIntervalSince(begun))) }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("READ \(label) TIMEOUT")
    }
    let unreadOnBoth = { storeA.statuses["crew-test"] == .unread && storeB.statuses["crew-test"] == .unread }
    let clearOnBoth = { storeA.statuses["crew-test"] == nil && storeB.statuses["crew-test"] == nil }
    report("start")
    storeA.markSeen(crew(storeA))
    try await wait("baseline read on A and B", until: clearOnBoth)

    let baseline = crew(storeA).canonicalSession?.position
    chat.send("Use the terminal to run: sleep 5 && echo left-probe. Then reply with just the output.", mode: .send)
    try await wait("prompt visible on A") { crew(storeA).canonicalSession?.position != baseline }
    storeA.markSeen(crew(storeA))
    try await wait("A read at the prompt") { crew(storeB).readPosition == crew(storeB).canonicalSession?.position && storeB.statuses["crew-test"] != .unread }
    report("chat left mid-turn")
    try await waitIdle(chat)
    try await wait("reply after leaving is unread on A and B", until: unreadOnBoth)
    report("after reply")
    storeB.markSeen(crew(storeB))
    try await wait("opened on B clears A and B", until: clearOnBoth)
    report("after B read")

    chat.send("Reply with exactly: unseen-probe", mode: .send)
    try await waitIdle(chat)
    try await wait("unseen turn is unread on A and B", until: unreadOnBoth)
    storeA.markSeen(crew(storeA))
    try await wait("opened on A clears A and B", until: clearOnBoth)
    report("after A read")

    let watcher = Task {
        while !Task.isCancelled {
            storeA.markSeen(crew(storeA))
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    let sent = Date.now
    chat.send("Use the terminal to run: sleep 6 && echo visible-probe. Then reply with just the output.", mode: .send)
    var timeline: [String] = []
    var finishedAt: Date?
    while finishedAt.map({ Date.now.timeIntervalSince($0) < 8 }) ?? true {
        if finishedAt == nil, !chat.isRunning, Date.now.timeIntervalSince(sent) > 2 { finishedAt = .now }
        if timeline.last?.hasPrefix(status(storeB)) != true { timeline.append(String(format: "%@ from +%.1fs", status(storeB), Date.now.timeIntervalSince(sent))) }
        try await Task.sleep(for: .milliseconds(100))
    }
    watcher.cancel()
    print(String(format: "READ visible send, turn took %.1fs; B timeline: %@", (finishedAt ?? .now).timeIntervalSince(sent), timeline.joined(separator: ", ")))
    report("after visible send")

    let stale = crew(storeB)
    chat.send("Reply with exactly: hidden-probe", mode: .send)
    try await waitIdle(chat)
    try await wait("unseen turn is unread on A and B", until: unreadOnBoth)
    let revision = crew(storeA).readRevision ?? 0
    storeA.markSeen(crew(storeA))
    storeB.markSeen(crew(storeB))
    try await wait("simultaneous marks settle") { clearOnBoth() && crew(storeA).readRevision == crew(storeB).readRevision && crew(storeA).readRevision != revision }
    try await Task.sleep(for: .seconds(3))
    report("after simultaneous marks")
    print("READ revision delta \((crew(storeB).readRevision ?? 0) - revision), markers == position", crew(storeA).readPosition == crew(storeA).canonicalSession?.position && crew(storeB).readPosition == crew(storeB).canonicalSession?.position)

    let marker = crew(storeB).readPosition
    storeB.markSeen(stale)
    try await Task.sleep(for: .seconds(4))
    print("READ stale markSeen kept marker", crew(storeA).readPosition == marker && crew(storeB).readPosition == marker)
    print("READ unread clears queued by A: \(storeA.clearedUnread.count)")
    await peerGateway.disconnect()
}

if phases.contains("cleared") {
    nonisolated struct CrewMarker: Encodable, Sendable {
        let name = "crew-test"
        let ui_meta: [String: ReadPosition?]
        let ui_meta_expected_revisions: [String: Int]
    }
    func writeMarker(_ marker: ReadPosition?) async throws {
        let revision = try await crewTest().readRevision ?? 0
        let reply = try await gateway.call("profiles.configure", CrewMarker(ui_meta: ["crew": marker], ui_meta_expected_revisions: ["crew": revision]), as: JSONValue.self)
        print("CLEARED wrote \(marker.map { "\($0.messages)" } ?? "nil"):", reply)
    }
    let original = try await crewTest()
    guard let position = original.canonicalSession?.position, position.messages > 0 else { print("CLEARED crew-test has no Bot Chat rows"); exit(1) }
    try await writeMarker(ReadPosition(session: position.session, messages: position.messages + 5))
    for _ in 0..<2 {
        let bot = try await crewTest()
        print("CLEARED roster count \(bot.canonicalSession?.messageCount ?? -1) (was \(position.messages)), marker \(bot.readPosition?.messages ?? -1), lastRead \(bot.lastRead?.messages ?? -1)")
    }
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    func wait(_ label: String, until done: () async throws -> Bool) async throws {
        let begun = Date.now
        while Date.now.timeIntervalSince(begun) < 15 {
            if try await done() { return print(String(format: "CLEARED %@ after %.2fs", label, Date.now.timeIntervalSince(begun))) }
            try await Task.sleep(for: .milliseconds(200))
        }
        print("CLEARED \(label) TIMEOUT")
    }
    try await wait("store rewrote the marker to the current count by itself") { try await crewTest().readPosition == position }
    try await Task.sleep(for: .seconds(3))
    print("CLEARED status after the drop: \(store.statuses["crew-test"].map { "\($0)" } ?? "idle"), read pushes: \(store.takeClearedUnread().count), count still \(try await crewTest().canonicalSession?.messageCount ?? -1)")
    try await writeMarker(original.readPosition)
    print("CLEARED restored", try await crewTest().readPosition == original.readPosition)
}

if phases.contains("a2ui") {
    record("a2ui-turn")
    let skill = try String(contentsOf: URL(fileURLWithPath: #filePath).appending(path: "../../../Sources/Profile/crew-ui.SKILL.md").standardized, encoding: .utf8)
    var install = hermesRequest("api/skills/content", on: server, json: ["name": "crew-ui", "content": skill, "profile": "crew-test"])
    install.httpMethod = "PUT"
    _ = try await fetch(install, with: urlSession, as: JSONValue.self)
    chat.send(env["A2UI_PROMPT"] ?? "Compare the last 7 days of weather in Stockholm as a chart", mode: .send)
    try await waitIdle(chat)
    show("a2ui", chat)
    let reply = outDir.appending(path: "a2ui-reply.md")
    try (chat.transcript.turns.last?.reply ?? "").write(to: reply, atomically: true, encoding: .utf8)
    print("REPLY", reply.path)
}

if phases.contains("mention") {
    record("mention-turn")
    let roster = try await gateway.call("profiles.list", ["include_sessions": true], as: BotRoster.self).profiles
    let start = chat.transcript.turns.count
    chat.send("@test-bot hi", mentioning: roster.filter { $0.name == "test-bot" }, mode: .send)
    try await waitIdle(chat)
    try await waitIdle(chat, timeout: 180) { !$0.isRunning && $0.transcript.turns.last?.delivery != nil }
    for turn in chat.transcript.turns.dropFirst(start) {
        print(chat.transcript.visible.turns.contains { $0.id == turn.id } ? "SHOWN  " : "HIDDEN ", turn.prompt?.text ?? turn.notice ?? turn.delivery ?? "-", "|", turn.reply)
    }
}

if phases.contains("record") {
    let scenario = CommandLine.arguments.last ?? ""
    guard ["bot-mention", "open-target", "delivery-failure"].contains(scenario) else { print("unknown scenario \(scenario)"); exit(1) }
    let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/scenarios/\(scenario)").standardized
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let peerName = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let names = ["crew-test", peerName]
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user"), (env["HERMES_PASSWORD"] ?? "", "***"), (peerName, "crew-test-peer")].filter { $0.0.count > 2 }
    func save(_ name: String, _ value: JSONValue) throws {
        let text = scrubs.reduce(String(decoding: try pretty.encode(value), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }.replacing(/crew-test-[0-9a-f]{6}/, with: "crew-test-old").replacing(/\/opt\/data\/[^\s"'\\]*/, with: "/opt/hermes/data").replacing(/uid:[0-9]+/, with: "uid:user")
        try Data((text + "\n").utf8).write(to: folder.appending(path: "\(name).json"))
        print("RECORDED \(name).json")
    }
    func roster() async throws -> (raw: JSONValue, bots: [Bot]) {
        let raw = try await gateway.call("profiles.list", ["include_sessions": true], as: JSONValue.self)
        guard case .object(let object) = raw, case .array(let profiles) = object["profiles"] else { return (.object(["profiles": .array([])]), []) }
        let kept = profiles.filter { if case .object(let profile) = $0, case .string(let name) = profile["name"] { names.contains(name) } else { false } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (.object(["profiles": .array(kept)]), try decoder.decode([Bot].self, from: encoder.encode(JSONValue.array(kept))))
    }
    func live(of bots: [Bot]) async throws -> (raw: JSONValue, sessions: [LiveSession]) {
        let keys = Set(bots.compactMap(\.canonicalSession).flatMap { [$0.id.rawValue, $0.resolvedID.rawValue] })
        let raw = try await gateway.call("session.active_list", [String: String](), as: JSONValue.self)
        guard case .object(let object) = raw, case .array(let sessions) = object["sessions"] else { return (.object(["sessions": .array([])]), []) }
        let kept = sessions.filter { if case .object(let session) = $0, case .string(let key) = session["session_key"] { keys.contains(key) } else { false } }
        return (.object(["sessions": .array(kept)]), try JSONDecoder().decode([LiveSession].self, from: encoder.encode(JSONValue.array(kept))))
    }
    func rows(of bot: Bot, limit: Int) async throws -> [JSONValue] {
        guard let session = bot.canonicalSession else { return [] }
        let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: bot.name, on: server, limit: limit))
        guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { return [] }
        let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "reasoning", "reasoning_content", "display_kind"]
        return messages.map { row in if case .object(let object) = row { .object(object.filter { keys.contains($0.key) }) } else { row } }
    }

    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    do {
        try await store.create(NewProfile(name: peerName, description: "Crew scenario peer", soul: "You are Crew Peer, a temporary probe bot. When another agent messages you, answer it by sending one short greeting back with your message_agent tool.", cloneFrom: nil), via: gateway) { meta in
            meta = BotMeta(title: "Crew Peer", shape: "hexagon", color: "#14b8a6", custom: true, imageKind: "shape", expression: "happy")
        }
        guard let peer = store.bots.first(where: { $0.name == peerName }), let sender = store.bots.first(where: { $0.name == "crew-test" }), let senderSession = sender.canonicalSession else { throw HermesError.invalidResponse }
        store.markSeen(sender)
        for _ in 0..<60 {
            if let bot = try await roster().bots.first(where: { $0.name == "crew-test" }), bot.readPosition == bot.canonicalSession?.position { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let before = try await roster()
        try save("profiles.before", before.raw)
        let firstRow = try await history(of: senderSession.resolvedID, profile: sender.name, on: server, with: urlSession, limit: 1).map(\.id).max() ?? 0
        let peerChats = ChatSessions()
        if scenario == "delivery-failure" {
            var changes = ProfileChanges(name: peerName)
            changes.model = "gpt-crew-test-missing"
            changes.provider = "openai-codex"
            changes.confirmExpensiveModel = true
            print("peer model change:", try await gateway.call("profiles.configure", changes, as: JSONValue.self))
        }
        if scenario == "open-target" {
            peerChats.open(peer, on: gateway, urlSession: urlSession)
            try await Task.sleep(for: .seconds(3))
        }
        var peerState = ""

        chat.send("@\(peerName) hi", mentioning: [peer], mode: .send)
        var duringSaved = false
        var quietSince: Date?
        let started = Date.now
        while Date.now.timeIntervalSince(started) < 300 {
            try await Task.sleep(for: .milliseconds(250))
            let current = try await roster()
            let active = try await live(of: current.bots)
            peerChats.sync(with: current.bots)
            if let peerChat = peerChats.sessions[peerName] {
                let state = "open peer chat: \(peerChat.transcript.visible.turns.count) rows, running \(peerChat.isRunning), roster \(current.bots.first { $0.name == peerName }?.canonicalSession?.messageCount ?? 0) messages, \(active.sessions.first { $0.sessionKey == current.bots.first { $0.name == peerName }?.canonicalSession?.resolvedID }?.status ?? "-")"
                if state != peerState { print(String(format: "+%.1fs ", Date.now.timeIntervalSince(started)) + state) }
                peerState = state
            }
            let inHiddenTurn = chat.isRunning && chat.transcript.turns.last.map({ $0.agentMessage != nil || $0.delivery != nil }) == true
            if !duringSaved, inHiddenTurn, active.sessions.contains(where: { $0.status != "idle" }) {
                try save("profiles.during", current.raw)
                try save("active_list.during", active.raw)
                duringSaved = true
            }
            let settled = !chat.isRunning && chat.transcript.turns.last?.delivery != nil && active.sessions.allSatisfy { $0.status == "idle" }
            quietSince = settled ? quietSince ?? .now : nil
            if let quietSince, Date.now.timeIntervalSince(quietSince) > 20 { break }
        }
        if !duringSaved { print("WARNING: never saw crew-test working on a hidden turn") }
        let after = try await roster()
        try save("profiles.after", after.raw)
        try save("active_list.after", try await live(of: after.bots).raw)
        for bot in after.bots {
            let history = try await rows(of: bot, limit: 500).filter { row in
                guard bot.name == "crew-test", case .object(let object) = row, case .number(let id) = object["id"] else { return true }
                return id > Double(firstRow)
            }
            let file = bot.name == peerName ? "crew-test-peer" : bot.name
            try save("\(file).history", .array(history))
            try save("\(file).preview", .array(try await rows(of: bot, limit: 20)))
        }
        if let peerChat = peerChats.sessions[peerName], let session = after.bots.first(where: { $0.name == peerName })?.canonicalSession {
            let fresh = Transcript(history: try await history(of: session.resolvedID, profile: peerName, on: server, with: urlSession))
            print(peerChat.transcript.visible.turns.map(\.work.count) == fresh.visible.turns.map(\.work.count) ? "OPEN PEER CHAT MATCHES HISTORY" : "OPEN PEER CHAT STALE")
        }
        for turn in chat.transcript.turns.suffix(4) {
            print(chat.transcript.visible.turns.contains { $0.id == turn.id } ? "SHOWN  " : "HIDDEN ", turn.prompt?.text ?? turn.delivery ?? "-", "|", turn.reply)
        }
    } catch {
        print("RECORD FAILED", error)
    }
    await store.reload(gateway)
    if let peer = store.bots.first(where: { $0.name == peerName }) { try await store.delete(peer, via: gateway, urlSession: urlSession) }
    print(store.bots.contains { $0.name == peerName } ? "PEER NOT DELETED" : "peer deleted")
}

if phases.contains("long-chat") {
    let chat = try await attached(try await crewTest())
    let prompts = [
        "I want to buy a watch as a gift for myself, budget around 3000 kr. Give me five candidates with a short paragraph on each and why it would feel special to own.",
        "Compare the two you like most in a markdown table: price, size, movement, water resistance and where to buy in Sweden. Then a paragraph on which you'd pick.",
        "Explain how a sourdough starter works, with headings for feeding, timing and troubleshooting, and a bulleted checklist at the end.",
        "Plan a three-day weekend in Lofoten in late September: one section per day, morning, afternoon and evening, plus a packing list.",
        "Write a short Swift function that groups an array of dates by calendar day, in a code block, and explain it in two paragraphs.",
        "Summarise everything we talked about in this chat so far as a numbered list, one or two sentences per item.",
    ]
    var firstRow = 0
    if let start = try await crewTest().canonicalSession {
        firstRow = try await history(of: start.resolvedID, profile: "crew-test", on: server, with: urlSession, limit: 1).map(\.id).max() ?? 0
    }
    for prompt in prompts {
        chat.send(prompt, mode: .send)
        try await Task.sleep(for: .seconds(2))
        try await waitIdle(chat)
        show("long-chat", chat)
    }
    try await Task.sleep(for: .seconds(3))
    guard let session = try await crewTest().canonicalSession else { print("no session"); exit(1) }
    let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: "crew-test", on: server, limit: 500))
    guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { print("no rows"); exit(1) }
    let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "reasoning", "reasoning_content", "display_kind"]
    let kept = messages.compactMap { row -> JSONValue? in
        guard case .object(let object) = row, case .number(let id) = object["id"], id > Double(firstRow) else { return nil }
        return .object(object.filter { keys.contains($0.key) })
    }
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user")].filter { $0.0.count > 2 }
    let text = scrubs.reduce(String(decoding: try pretty.encode(JSONValue.object(["messages": .array(kept)])), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }.replacingOccurrences(of: "/opt/data/", with: "/opt/hermes/data/")
    let file = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/chat.long-replies.history.json").standardized
    try Data((text + "\n").utf8).write(to: file)
    print("RECORDED \(kept.count) rows to \(file.path)")
}

if phases.contains("history") {
    let reloaded = try await attached(try await crewTest())
    print("== full history")
    for line in summary(reloaded.transcript) { print("  ", line) }
}

eventLog = nil
await gateway.disconnect()
exit(0)
