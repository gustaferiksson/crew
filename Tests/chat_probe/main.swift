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

if phases.contains("room-list") {
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    func save(_ method: String, _ file: String) async throws {
        let value = try await gateway.call(method, [String: String](), as: JSONValue.self)
        let url = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/rooms/\(file)").standardized
        try (pretty.encode(value) + Data("\n".utf8)).write(to: url)
        print("RECORDED", file)
    }
    let names = (0..<2).map { _ in "crew-test-\(UUID().uuidString.prefix(6).lowercased())" }
    var roomIDs: [String] = []
    do {
        try await save("groups.capabilities", "capabilities.json")
        for (index, name) in names.enumerated() {
            try await store.create(NewProfile(name: name, description: "Crew room list probe", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Peer \(index + 1)" }
        }
        await store.reload(gateway)
        let bots = try ["crew-test", names[0], names[1]].map { name in try store.bots.first { $0.name == name } ?? { throw HermesError.invalidResponse }() }
        for (title, pair) in [("Crew list one", [bots[0], bots[1]]), ("Crew list two", [bots[0], bots[2]]), ("Crew list peers", [bots[1], bots[2]])] {
            let roomID = "room-\(UUID().uuidString.lowercased())"
            let members: [JSONValue] = pair.map { .object(["member_id": .string($0.name), "profile": .string($0.name), "handle": .string($0.handle), "display_name": .string($0.title)]) }
            _ = try await gateway.call("groups.create", ["room_id": .string(roomID), "name": .string(title), "members": .array(members)] as [String: JSONValue], as: JSONValue.self)
            roomIDs.append(roomID)
        }
        try await save("groups.list", "list.json")
    } catch {
        print("ROOM LIST FAILED", error)
    }
    for roomID in roomIDs { _ = try? await gateway.call("groups.disband", ["room_id": roomID], as: JSONValue.self) }
    for name in names {
        if let bot = store.bots.first(where: { $0.name == name }) { try? await store.delete(bot, via: gateway, urlSession: urlSession) }
    }
    await store.reload(gateway)
    print(store.bots.contains { names.contains($0.name) } ? "THROWAWAY NOT DELETED" : "throwaways deleted")
    exit(0)
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

if phases.contains("steer-answer-after-tools") {
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    do {
        try await store.create(NewProfile(name: name, description: "Crew scenario bot", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Steer" }
        await store.reload(gateway)
        guard let fresh = store.bots.first(where: { $0.name == name }) else { throw HermesError.invalidResponse }
        let chat = try await attached(fresh)
        record("steer-answer-after-tools-turn")
        chat.send("Use the terminal to run: sleep 8 && echo step-one. Then run: echo step-two. Then reply with both outputs.", mode: .send)
        try await waitIdle(chat, timeout: 60) { chat in
            chat.transcript.turns.last?.work.contains { if case .tool = $0.kind { true } else { false } } ?? false
        }
        chat.send("Is whoami root? Check with the terminal before you say anything, answer in one short sentence, then carry on.", mode: .steer)
        try await waitIdle(chat)
        show("steer-answer-after-tools live", chat)
        await store.reload(gateway)
        guard let ran = store.bots.first(where: { $0.name == name }), let session = ran.canonicalSession else { throw HermesError.invalidResponse }
        show("steer-answer-after-tools history", try await attached(ran))
        let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: name, on: server, limit: 30))
        guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { throw HermesError.invalidResponse }
        let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "reasoning", "reasoning_content", "display_kind", "display_content", "display_commentary", "display_reasoning", "finish_reason"]
        let kept = messages.map { row in if case .object(let object) = row { JSONValue.object(object.filter { keys.contains($0.key) }) } else { row } }
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try pretty.encode(JSONValue.array(kept)).write(to: outDir.appending(path: "steer-answer-after-tools.history.json"))
        print("history rows written to", outDir.appending(path: "steer-answer-after-tools.history.json").path)
    } catch {
        print("STEER FAILED", error)
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

if phases.contains("voice") {
    let bot = try await crewTest()
    let word = "voice-\(UUID().uuidString.prefix(4).lowercased())"
    let (_, snapshot) = try await openBotChat(bot.canonicalSession?.id, profile: bot.name, via: gateway)
    _ = try await gateway.call("prompt.submit", ["session_id": snapshot.sessionID.rawValue, "text": "Reply with just the word \(word)."], as: JSONValue.self)
    await gateway.disconnect()
    print("submitted and disconnected at once, polling history")
    for _ in 0..<60 {
        try await Task.sleep(for: .seconds(3))
        guard let stored = snapshot.storedSessionID ?? bot.canonicalSession?.resolvedID else { break }
        let turn = Transcript(history: try await history(of: stored, profile: "crew-test", on: server, with: urlSession, limit: 20)).turns.last
        guard turn?.prompt?.text.contains(word) == true, turn?.status != .streaming, let reply = turn?.reply, !reply.isEmpty else { continue }
        print(reply.contains(word) ? "VOICE OK reply after disconnect: \(reply.prefix(60))" : "VOICE REPLY MISMATCH: \(reply.prefix(60))")
        exit(0)
    }
    print("VOICE TIMEOUT: no reply in history")
    exit(1)
}

if phases.contains("ask") {
    let bot = try await crewTest()
    let started = ContinuousClock.now
    let (_, snapshot) = try await openBotChat(bot.canonicalSession?.id, profile: bot.name, via: gateway)
    let ask = { (text: String, seconds: Int) in
        try await BotAnswer.wait(in: snapshot.sessionID, for: gateway.events(), after: { try await gateway.call("prompt.submit", ["session_id": snapshot.sessionID.rawValue, "text": text], as: SubmitStatus.self) }, until: .now + .seconds(seconds))
    }
    let word = "ask-\(UUID().uuidString.prefix(4).lowercased())"
    let answer = try await ask("Reply with just the word \(word), in bold.", 20)
    print("ASK answer \(answer), speech \(BotAnswer.speech(from: { if case .reply(let text) = answer { text } else { "" } }())), \(ContinuousClock.now - started) from open")
    let slow = try await ask("Write a 400-word story about a lighthouse.", 1)
    print("ASK long turn with a 1 s deadline: \(slow)")
    let busy = try await ask("Reply with just: queued", 3)
    print("ASK while busy: \(busy)")
    exit(answer == .reply("**\(word)**") || answer == .reply(word) ? 0 : 1)
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

if phases.contains("usage") {
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/usage").standardized
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let bot = try await crewTest()
    let (_, snapshot) = try await openBotChat(bot.canonicalSession?.resolvedID, profile: "crew-test", via: gateway)
    let session = ["session_id": snapshot.sessionID.rawValue]
    if let stored = bot.canonicalSession?.resolvedID {
        let resumed = try await gateway.call("session.resume", ["session_id": .string(stored.rawValue), "profile": .string("crew-test"), "omit_messages": .bool(true)] as [String: JSONValue], as: JSONValue.self)
        guard case .object(var reply) = resumed, case .object(let info) = reply["info"] else { exit(1) }
        reply = reply.filter { ["session_id", "message_count", "running"].contains($0.key) }
        reply["info"] = .object(info.filter { ["usage", "stored_session_id"].contains($0.key) })
        try (pretty.encode(JSONValue.object(reply)) + Data("\n".utf8)).write(to: folder.appending(path: "session.resume.v0.23.0.json"))
    }
    for method in ["session.usage", "session.context_breakdown"] {
        let reply = try await gateway.call(method, session, as: JSONValue.self)
        try (pretty.encode(reply) + Data("\n".utf8)).write(to: folder.appending(path: "\(method).v0.23.0.json"))
        print("RECORDED", method, String(decoding: try pretty.encode(reply), as: UTF8.self).prefix(1500))
    }
    record("usage-turn")
    let chat = try await attached(bot)
    chat.send("Reply with just: ok", mode: .send)
    try await waitIdle(chat)
    exit(0)
}

if phases.contains("usage-compact") {
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/usage").standardized
    let chat = try await attached(try await crewTest())
    chat.send("Reply with just: ok", mode: .send)
    try await waitIdle(chat)
    print("BEFORE", String(describing: chat.context))
    let (_, snapshot) = try await openBotChat(try await crewTest().canonicalSession?.resolvedID, profile: "crew-test", via: gateway)
    let session = ["session_id": snapshot.sessionID.rawValue]
    _ = try await gateway.call("session.compress", session, as: JSONValue.self, timeout: .seconds(300))
    for method in ["session.usage", "session.context_breakdown"] {
        let reply = try await gateway.call(method, session, as: JSONValue.self)
        try (pretty.encode(reply) + Data("\n".utf8)).write(to: folder.appending(path: "\(method).after-compact.v0.23.0.json"))
        print("RECORDED", method, String(decoding: try pretty.encode(reply), as: UTF8.self).prefix(400))
    }
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

if phases.contains("room-paused") {
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let roomID = "room-\(UUID().uuidString.lowercased())"
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user"), (name, "crew-test-peer")].filter { $0.0.count > 2 }
    func save(_ value: JSONValue, _ file: String) throws {
        let url = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/rooms/\(file)").standardized
        let text = scrubs.reduce(String(decoding: try pretty.encode(value), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        try Data((text + "\n").utf8).write(to: url)
        print("RECORDED", file)
    }
    func state() async throws -> JSONValue {
        try await gateway.call("groups.state", ["room_id": roomID], as: JSONValue.self)
    }
    func log() async throws -> [JSONValue] {
        var events: [JSONValue] = []
        var cursor = 0
        while true {
            guard case .object(let page) = try await gateway.call("groups.log", ["room_id": .string(roomID), "since_seq": .number(Double(cursor))] as [String: JSONValue], as: JSONValue.self),
                  case .array(let rows) = page["events"] ?? .null, case .number(let next) = page["cursor"] ?? .null else { throw HermesError.invalidResponse }
            events += rows
            cursor = Int(next)
            guard page["has_more"] == .bool(true) else { return events }
        }
    }
    func driver(_ state: JSONValue) -> [String: JSONValue] {
        guard case .object(let s) = state, case .object(let driver) = s["driver_status"] ?? .null else { return [:] }
        return driver
    }
    func activities(_ events: [JSONValue]) -> [String] {
        events.compactMap { event in
            guard case .object(let e) = event, e["kind"] == .string("room.activity"), case .object(let p) = e["payload"] ?? .null, case .string(let status) = p["status"] ?? .null else { return nil }
            return status
        }
    }
    func waitForOutcome(after count: Int, saveWorking: Bool) async throws -> [JSONValue] {
        var savedWorking = !saveWorking
        for _ in 0..<180 {
            try await Task.sleep(for: .seconds(2))
            let current = try await state()
            let driver = driver(current)
            if !savedWorking, case .array(let rows) = driver["member_activity"] ?? .null, rows.contains(where: { if case .object(let r) = $0 { r["started_at"] != nil } else { false } }) {
                try save(current, "paused.state.working.json")
                savedWorking = true
            }
            if driver["working"] == .bool(false) {
                let events = try await log()
                if activities(events).count > count { return events }
            }
        }
        throw HermesError.invalidResponse
    }
    var created = false
    do {
        try await store.create(NewProfile(name: name, description: "Crew room probe", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Peer" }
        await store.reload(gateway)
        guard let peer = store.bots.first(where: { $0.name == name }), let test = store.bots.first(where: { $0.name == "crew-test" }) else { throw HermesError.invalidResponse }
        let members: [JSONValue] = [test, peer].map { .object(["member_id": .string($0.name), "profile": .string($0.name), "handle": .string($0.handle), "display_name": .string($0.title)]) }
        _ = try await gateway.call("groups.create", ["room_id": .string(roomID), "name": .string("Crew probe room"), "members": .array(members)] as [String: JSONValue], as: JSONValue.self)
        created = true
        print("DRIVER", driver(try await state()).filter { ["max_rounds", "max_continues", "working"].contains($0.key) })
        let text = "@\(test.handle) @\(peer.handle) Relay game: answer in one short sentence and end it by @-mentioning the other member by handle, every time."
        _ = try await gateway.call("groups.send", ["room_id": .string(roomID), "event_id": .string("crew-probe-\(UUID().uuidString.lowercased())"), "payload": .object(["text": .string(text), "thread_id": .string("crew-probe")])] as [String: JSONValue], as: JSONValue.self)
        let paused = try await waitForOutcome(after: 0, saveWorking: true)
        print("OUTCOMES", activities(paused))
        try save(.array(paused), "paused.log.json")
        try save(try await state(), "paused.state.json")
        guard activities(paused).last == "bounded" else { throw HermesError.invalidResponse }
        let bounded = paused.last { if case .object(let e) = $0 { e["kind"] == .string("room.activity") } else { false } }
        guard case .object(let b) = bounded, case .object(let payload) = b["payload"] ?? .null, let discussion = payload["discussion_event_id"] else { throw HermesError.invalidResponse }
        for params: [String: JSONValue] in [["room_id": .string(roomID), "task_id": .string("crew-probe-missing")], ["room_id": .string(roomID), "task_id": .string("crew-probe-missing"), "member_id": .string(test.name), "execution_generation": .number(1)]] {
            do { print("RETRY", params.keys.sorted(), try await gateway.call("groups.retry", params, as: JSONValue.self)) } catch { print("RETRY", params.keys.sorted(), error) }
        }
        let continued = try await gateway.call("groups.continue", ["room_id": .string(roomID), "discussion_event_id": discussion], as: JSONValue.self)
        try save(continued, "continue.reply.json")
        print("AFTER CONTINUE working", driver(try await state())["working"] ?? .null)
        do { print("SECOND CONTINUE", try await gateway.call("groups.continue", ["room_id": .string(roomID), "discussion_event_id": discussion], as: JSONValue.self)) } catch { print("SECOND CONTINUE", error) }
        let after = try await waitForOutcome(after: activities(paused).count, saveWorking: false)
        print("OUTCOMES", activities(after))
        try save(.array(after), "continued.log.json")
        _ = try await gateway.call("groups.stop", ["room_id": .string(roomID), "cancel_id": .string("crew-probe-stop-\(UUID().uuidString.lowercased())")] as [String: JSONValue], as: JSONValue.self)
        do { print("CONTINUE AFTER STOP", try await gateway.call("groups.continue", ["room_id": .string(roomID), "discussion_event_id": discussion], as: JSONValue.self)) } catch { print("CONTINUE AFTER STOP", error) }
    } catch {
        print("ROOM PAUSED FAILED", error)
    }
    if created { _ = try? await gateway.call("groups.disband", ["room_id": roomID], as: JSONValue.self) }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try? await store.delete(bot, via: gateway, urlSession: urlSession) }
    await store.reload(gateway)
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("room-context") {
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let roomID = "room-\(UUID().uuidString.lowercased())"
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user"), (name, "crew-test-peer"), (roomID, "room-context-probe")].filter { $0.0.count > 2 }
    func save(_ value: JSONValue, _ file: String) throws {
        let url = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/rooms/\(file)").standardized
        let text = scrubs.reduce(String(decoding: try pretty.encode(value), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        try Data((text + "\n").utf8).write(to: url)
        print("RECORDED", file)
    }
    func state() async throws -> JSONValue {
        try await gateway.call("groups.state", ["room_id": roomID], as: JSONValue.self)
    }
    func log() async throws -> [JSONValue] {
        var events: [JSONValue] = []
        var cursor = 0
        while true {
            guard case .object(let page) = try await gateway.call("groups.log", ["room_id": .string(roomID), "since_seq": .number(Double(cursor))] as [String: JSONValue], as: JSONValue.self),
                  case .array(let rows) = page["events"] ?? .null, case .number(let next) = page["cursor"] ?? .null else { throw HermesError.invalidResponse }
            events += rows
            cursor = Int(next)
            guard page["has_more"] == .bool(true) else { return events }
        }
    }
    func kinds(_ events: [JSONValue]) -> [String] {
        events.compactMap { event in
            guard case .object(let e) = event, case .string(let kind) = e["kind"] ?? .null else { return nil }
            let payload = if case .object(let p) = e["payload"] ?? .null { p } else { [String: JSONValue]() }
            let actor = if case .object(let a) = e["actor"] ?? .null, case .string(let id) = a["id"] ?? .null { id } else { "-" }
            let text = if case .string(let t) = payload["text"] ?? .null { " \"\(t.prefix(60))\"" } else { "" }
            return "\(kind) by \(actor) thread \(payload["thread_id"].map { "\($0)" } ?? "-")\(text)"
        }
    }
    func context(_ params: [String: String]) async -> JSONValue? {
        var full = params.mapValues { JSONValue.string($0) }
        full["room_id"] = .string(roomID)
        full["event_id"] = .string("crew-probe-context-\(UUID().uuidString.lowercased())")
        do {
            let reply = try await gateway.call("groups.context", full, as: JSONValue.self)
            print("CONTEXT", params.keys.sorted(), "->", reply)
            return reply
        } catch {
            print("CONTEXT", params.keys.sorted(), "FAILED", error)
            return nil
        }
    }
    func send(_ text: String, thread: String) async throws {
        _ = try await gateway.call("groups.send", ["room_id": .string(roomID), "event_id": .string("crew-probe-\(UUID().uuidString.lowercased())"), "payload": .object(["text": .string(text), "thread_id": .string(thread)])] as [String: JSONValue], as: JSONValue.self)
    }
    func settle(_ label: String) async throws {
        var sawWorking = false
        for tick in 0..<150 {
            try await Task.sleep(for: .seconds(tick < 10 ? 0.5 : 2))
            guard case .object(let s) = try await state(), case .object(let driver) = s["driver_status"] ?? .null else { continue }
            if driver["working"] == .bool(true) { sawWorking = true }
            if tick < 6 { print(label, "tick", tick, "working", driver["working"] ?? .null) }
            if driver["working"] == .bool(false), tick > 6 { break }
        }
        print(label, "saw working", sawWorking)
    }
    var created = false
    var jobID: String?
    do {
        try await store.create(NewProfile(name: name, description: "Crew room probe: answers questions about travel and dates", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Peer" }
        await store.reload(gateway)
        guard let peer = store.bots.first(where: { $0.name == name }), let test = store.bots.first(where: { $0.name == "crew-test" }) else { throw HermesError.invalidResponse }
        let members: [JSONValue] = [test, peer].map { .object(["member_id": .string($0.name), "profile": .string($0.name), "handle": .string($0.handle), "display_name": .string($0.title)]) }
        _ = try await gateway.call("groups.create", ["room_id": .string(roomID), "name": .string("Crew context room"), "members": .array(members)] as [String: JSONValue], as: JSONValue.self)
        created = true
        let routineOnly = env["ROUTINE_ONLY"] != nil
        if !routineOnly {
        try save(try await state(), "context.state.empty.json")

        _ = await context(["purpose": "Plan the team offsite in Lisbon", "notes": "Budget is 900 EUR per person.\nNobody flies before 08:00."])
        _ = await context(["purpose": "Plan the team offsite in Lisbon", "notes": "Budget is 900 EUR per person.\nNobody flies before 08:00.", "routing": "lead", "lead_member_id": test.name])
        _ = await context(["purpose": "Plan the team offsite in Lisbon, 12 to 14 May", "notes": "Budget is 900 EUR per person.\nNobody flies before 08:00."])
        try save(try await state(), "context.state.lead.json")
        _ = await context(["purpose": "x", "notes": "", "routing": "lead", "lead_member_id": ""])
        _ = await context(["purpose": "x", "notes": "", "routing": "lead", "lead_member_id": test.handle + "-nobody"])
        _ = await context(["purpose": String(repeating: "a", count: 501), "notes": ""])
        _ = await context(["purpose": "x", "notes": String(repeating: "é", count: 2049)])
        _ = await context(["purpose": "x", "notes": "", "routing": "sometimes"])
        _ = await context(["purpose": "x"])

        try await send("Which day should we fly out?", thread: "crew-probe-lead")
        try await settle("LEAD")
        try await send("And which airline is cheapest?", thread: "crew-probe-lead")
        try await settle("LEAD SAME THREAD")
        print(kinds(try await log()).joined(separator: "\n"))

        let modes = if case .object(let s) = try await state(), case .object(let d) = s["driver_status"] ?? .null { d["routing_modes"] } else { JSONValue?.none }
        print("ROUTING MODES", modes ?? .null)
        _ = await context(["purpose": "Plan the team offsite in Lisbon, 12 to 14 May", "notes": "Budget is 900 EUR per person.\nNobody flies before 08:00.", "routing": "auto"])
        try await send("What is the weather like in Lisbon in May?", thread: "crew-probe-auto")
        try await settle("AUTO")
        try save(try await state(), "context.state.auto.json")
        _ = await context(["purpose": "", "notes": "", "routing": "everyone"])
        }

        let deliver = "room:\(roomID)@default"
        let added = try await gateway.call("cron.manage", [
            "action": .string("add"), "profile": .string(name), "name": .string("[bot:\(name)] Daily fares"), "schedule": .string("every 1440m"),
            "prompt": .string("Reply with exactly this text and nothing else: Fares to Lisbon dropped to 129 EUR on TAP. @\(test.handle) can you check they fit the dates?"),
            "deliver": .string(deliver),
        ] as [String: JSONValue], as: JSONValue.self)
        guard case .object(let job) = added, case .string(let id) = job["job_id"] else { print("ADD FAILED", added); throw HermesError.invalidResponse }
        jobID = id
        print("ROUTINE added", id, "deliver", job["deliver"] ?? .null)
        var trigger = hermesRequest("api/cron/jobs/\(id)/trigger", on: server, json: [:])
        trigger.url?.append(queryItems: [URLQueryItem(name: "profile", value: name)])
        _ = try await fetch(trigger, with: urlSession, as: JSONValue.self)
        var posted = false
        for _ in 0..<120 where !posted {
            try await Task.sleep(for: .seconds(3))
            posted = kinds(try await log()).contains { $0.contains("by cron:") }
        }
        print("ROUTINE posted", posted)
        let listed = try await gateway.call("cron.manage", ["action": .string("list"), "profile": .string(name), "include_disabled": .bool(true)] as [String: JSONValue], as: JSONValue.self)
        if case .object(let l) = listed, case .array(let jobs) = l["jobs"] ?? .null {
            for job in jobs { if case .object(let j) = job { print("JOB", j["deliver"] ?? .null, j["last_status"] ?? .null, j["last_delivery_error"] ?? .null) } }
        }
        try await settle("ROUTINE")
        let final = try await log()
        try save(.array(final), routineOnly ? "context.routine.log.json" : "context.log.json")
        try save(try await state(), routineOnly ? "context.routine.state.json" : "context.state.json")
        print(kinds(final).joined(separator: "\n"))
    } catch {
        print("ROOM CONTEXT FAILED", error)
    }
    if let jobID { _ = try? await gateway.call("cron.manage", ["action": "remove", "profile": name, "name": jobID], as: JSONValue.self) }
    if created { _ = try? await gateway.call("groups.disband", ["room_id": roomID], as: JSONValue.self) }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try? await store.delete(bot, via: gateway, urlSession: urlSession) }
    await store.reload(gateway)
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("room-routing") {
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let roomID = "room-\(UUID().uuidString.lowercased())"
    var created = false
    do {
        try await store.create(NewProfile(name: name, description: "Crew room probe: answers questions about travel", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Peer" }
        await store.reload(gateway)
        guard let peer = store.bots.first(where: { $0.name == name }), let test = store.bots.first(where: { $0.name == "crew-test" }) else { throw HermesError.invalidResponse }
        let members: [JSONValue] = [test, peer].map { .object(["member_id": .string($0.name), "profile": .string($0.name), "handle": .string($0.handle), "display_name": .string($0.title)]) }
        _ = try await gateway.call("groups.create", ["room_id": .string(roomID), "name": .string("Crew routing room"), "members": .array(members)] as [String: JSONValue], as: JSONValue.self)
        created = true
        _ = try await gateway.call("groups.context", ["room_id": roomID, "event_id": "crew-probe-context-\(UUID().uuidString.lowercased())", "purpose": "", "notes": "", "routing": "lead", "lead_member_id": test.name], as: JSONValue.self)
        let roster = [test, peer].map { RoomMember(memberID: $0.name, profile: $0.name, handle: $0.handle, displayName: $0.title) }
        let room = Room(id: roomID, name: "Crew routing room", members: roster, createdAt: .now, updatedAt: .now)
        let session = GroupSession(room: room, gateway: gateway)
        Task { await session.run() }
        for text in ["Which day should we fly out?", "And which airline is cheapest?"] {
            session.send(text)
            for tick in 0..<150 {
                try await Task.sleep(for: .seconds(2))
                if tick > 3, !session.isAwaitingReply { break }
            }
        }
        let prompts = session.events.filter { $0.kind == "message.user" }
        let assignments = session.events.filter { $0.kind == "room.assignment" }
        print("PROMPT THREADS", prompts.map { $0.payload.threadID ?? "-" })
        print("ASSIGNMENTS", assignments.map { "\($0.payload.discussionEventID ?? "-") -> \($0.payload.memberIDs ?? [])" })
        let routedBoth = prompts.count == 2 && Set(assignments.compactMap(\.payload.discussionEventID)) == Set(prompts.map(\.eventID))
        print(routedBoth ? "PASS both messages routed by the lead" : "FAIL")
    } catch {
        print("ROOM ROUTING FAILED", error)
    }
    if created { _ = try? await gateway.call("groups.disband", ["room_id": roomID], as: JSONValue.self) }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try? await store.delete(bot, via: gateway, urlSession: urlSession) }
    await store.reload(gateway)
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("room-reply") {
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let roomID = "room-\(UUID().uuidString.lowercased())"
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    func save(_ value: JSONValue, _ file: String) throws {
        let url = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/rooms/\(file)").standardized
        try (pretty.encode(value) + Data("\n".utf8)).write(to: url)
        print("RECORDED", file)
    }
    func log() async throws -> [JSONValue] {
        var events: [JSONValue] = []
        var cursor = 0
        while true {
            guard case .object(let page) = try await gateway.call("groups.log", ["room_id": .string(roomID), "since_seq": .number(Double(cursor))] as [String: JSONValue], as: JSONValue.self),
                  case .array(let rows) = page["events"] ?? .null, case .number(let next) = page["cursor"] ?? .null else { throw HermesError.invalidResponse }
            events += rows
            cursor = Int(next)
            guard page["has_more"] == .bool(true) else { return events }
        }
    }
    var created = false
    var failures: [String] = []
    func check(_ ok: Bool, _ label: String) {
        print(ok ? "PASS" : "FAIL", label)
        if !ok { failures.append(label) }
    }
    do {
        try await store.create(NewProfile(name: name, description: "Crew room probe: answers questions about travel", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Peer" }
        await store.reload(gateway)
        guard let peer = store.bots.first(where: { $0.name == name }), let test = store.bots.first(where: { $0.name == "crew-test" }) else { throw HermesError.invalidResponse }
        let members: [JSONValue] = [test, peer].map { .object(["member_id": .string($0.name), "profile": .string($0.name), "handle": .string($0.handle), "display_name": .string($0.title)]) }
        _ = try await gateway.call("groups.create", ["room_id": .string(roomID), "name": .string("Crew reply room"), "members": .array(members)] as [String: JSONValue], as: JSONValue.self)
        created = true
        _ = try await gateway.call("groups.context", ["room_id": roomID, "event_id": "crew-probe-context-\(UUID().uuidString.lowercased())", "purpose": "", "notes": "", "routing": "lead", "lead_member_id": test.name], as: JSONValue.self)
        let roster = [test, peer].map { RoomMember(memberID: $0.name, profile: $0.name, handle: $0.handle, displayName: $0.title) }
        let room = Room(id: roomID, name: "Crew reply room", members: roster, createdAt: .now, updatedAt: .now)
        let session = GroupSession(room: room, gateway: gateway)
        Task { await session.run() }
        func settle() async throws {
            for tick in 0..<150 {
                try await Task.sleep(for: .seconds(2))
                if tick > 3, !session.isAwaitingReply { break }
            }
        }
        func latestPrompt() -> RoomEvent? { session.events.last { $0.kind == "message.user" } }
        func answered(_ discussion: String) -> Set<String> {
            Set(session.events.filter { ["message.member", "turn.settled"].contains($0.kind) && $0.payload.discussionEventID == discussion }.compactMap(\.payload.memberID))
        }
        func assigned(_ discussion: String) -> Bool { session.events.contains { $0.kind == "room.assignment" && $0.payload.discussionEventID == discussion } }

        session.send("@\(peer.handle) Name one city in Portugal, in one short sentence.")
        try await settle()
        let opener = try latestPrompt() ?? { throw HermesError.invalidResponse }()
        let thread = opener.payload.threadID ?? ""
        let answer = try session.events.last { $0.kind == "message.member" && $0.payload.memberID == peer.name } ?? { throw HermesError.invalidResponse }()
        let toPeer = try session.reply(to: answer.eventID) ?? { throw HermesError.invalidResponse }()
        check(toPeer.handle == peer.handle && toPeer.thread == thread, "reply target is the peer in the opener's thread")
        session.send(toPeer.addressing("And one more city, in one short sentence?", replacing: nil), thread: toPeer.thread)
        try await settle()
        let handleReply = try latestPrompt() ?? { throw HermesError.invalidResponse }()
        check(handleReply.payload.threadID == thread, "@handle reply logged in the opener's thread")
        check(!assigned(handleReply.eventID), "@handle reply got no room.assignment")
        check(answered(handleReply.eventID) == [peer.name], "only the peer answered the @handle reply")
        check(session.events.contains { $0.kind == "message.member" && $0.payload.discussionEventID == handleReply.eventID && $0.payload.threadID == thread }, "the peer's answer is in the same thread")

        let toSelf = try session.reply(to: opener.eventID) ?? { throw HermesError.invalidResponse }()
        check(toSelf.handle == nil && toSelf.thread == thread, "reply to own message has no handle")
        session.send(toSelf.addressing("Each of you, answer with one word: sunny or rainy?", replacing: nil), thread: toSelf.thread)
        try await settle()
        let ownReply = try latestPrompt() ?? { throw HermesError.invalidResponse }()
        check(ownReply.payload.threadID == thread, "own reply logged in the opener's thread")
        check(!assigned(ownReply.eventID), "own reply got no room.assignment in a Lead room")
        check(answered(ownReply.eventID) == [test.name, peer.name], "both members took the own reply")

        let toTest = try session.reply(to: session.events.last { $0.kind == "message.member" && $0.payload.memberID == test.name }?.eventID ?? "") ?? toPeer
        session.send(toTest.addressing("Write a 250-word story about a lighthouse keeper in Porto.", replacing: nil), thread: thread)
        var running = false
        for _ in 0..<60 where !running {
            try await Task.sleep(for: .seconds(1))
            let state = try await gateway.call("groups.state", RoomParams(roomID: roomID), as: RoomState.self)
            running = state.driverStatus?.memberActivity?.contains { $0.status == "running" } == true
        }
        print("RUNNING before the superseding reply", running)
        session.send(toPeer.addressing("Never mind the story. Say hi in one word.", replacing: nil), thread: thread)
        try await settle()
        check(session.events.contains { $0.kind == "turn.cancelled" && $0.payload.reason == "superseded_by_newer_user_event" }, "a reply into a working thread supersedes the turn in flight")

        let final = try await log()
        try save(.array(final), "reply.log.json")
        try save(try await gateway.call("groups.state", ["room_id": roomID], as: JSONValue.self), "reply.state.json")
        for event in session.events { print(event.seq, event.kind, event.actor.id ?? "-", event.payload.threadID ?? "-", event.payload.reason ?? "", (event.payload.text ?? "").prefix(50)) }
        print(failures.isEmpty ? "PASS room-reply" : "FAIL room-reply \(failures)")
    } catch {
        print("ROOM REPLY FAILED", error)
    }
    if created { _ = try? await gateway.call("groups.disband", ["room_id": roomID], as: JSONValue.self) }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try? await store.delete(bot, via: gateway, urlSession: urlSession) }
    await store.reload(gateway)
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("room-history") {
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let roomID = "room-\(UUID().uuidString.lowercased())"
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    func save(_ value: JSONValue, _ file: String) throws {
        let url = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/rooms/\(file)").standardized
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (pretty.encode(value) + Data("\n".utf8)).write(to: url)
        print("RECORDED", file)
    }
    func list(_ title: String) async throws -> JSONValue {
        try await gateway.call("session.list", ["profile": .string("crew-test"), "title": .string(title), "include_hidden": .bool(true)] as [String: JSONValue], as: JSONValue.self)
    }
    var created = false
    do {
        try await store.create(NewProfile(name: name, description: "Crew room probe", soul: nil, cloneFrom: nil), via: gateway) { $0.title = "Crew Peer" }
        await store.reload(gateway)
        guard let peer = store.bots.first(where: { $0.name == name }), let test = store.bots.first(where: { $0.name == "crew-test" }) else { throw HermesError.invalidResponse }
        let members: [JSONValue] = [test, peer].map { .object(["member_id": .string($0.name), "profile": .string($0.name), "handle": .string($0.handle), "display_name": .string($0.title)]) }
        _ = try await gateway.call("groups.create", ["room_id": .string(roomID), "name": .string("Crew probe room"), "members": .array(members)] as [String: JSONValue], as: JSONValue.self)
        created = true
        for round in 1...Int(env["ROUNDS"] ?? "8")! {
            let text = "@\(test.handle) reply with one short sentence about the number \(round)."
            _ = try await gateway.call("groups.send", ["room_id": .string(roomID), "event_id": .string("crew-probe-\(UUID().uuidString.lowercased())"), "payload": .object(["text": .string(text), "thread_id": .string("crew-probe")])] as [String: JSONValue], as: JSONValue.self)
            for tick in 0..<90 {
                try await Task.sleep(for: .seconds(2))
                let state = try await gateway.call("groups.state", ["room_id": roomID], as: JSONValue.self)
                if case .object(let s) = state, case .object(let driver) = s["driver_status"] ?? .null, driver["working"] == .bool(false), tick > 2 { break }
            }
            print("ROUND", round)
        }
        let before = try await list("Group: \(roomID)")
        try save(before, "session.list.before.json")
        try save(try await list("Group: room-none"), "session.list.none.json")
        guard case .object(let page) = before, case .array(let rows) = page["sessions"] ?? .null, case .object(let row) = rows.first ?? .null, case .string(let id) = row["resolved_id"] ?? row["id"] ?? .null else { throw HermesError.invalidResponse }
        let resumed = try await gateway.call("session.resume", ["profile": .string("crew-test"), "session_id": .string(id), "omit_messages": .bool(true)] as [String: JSONValue], as: JSONValue.self)
        guard case .object(let resumedObject) = resumed, case .string(let runtime) = resumedObject["session_id"] ?? .null else { throw HermesError.invalidResponse }
        guard case .object(var reply) = try await gateway.call("session.compress", ["session_id": runtime], as: JSONValue.self, timeout: .seconds(660)) else { throw HermesError.invalidResponse }
        for key in ["messages", "info", "usage"] { reply[key] = nil }
        try save(.object(reply), "session.compress.json")
        try save(try await list("Group: \(roomID)"), "session.list.after.json")
    } catch {
        print("ROOM HISTORY FAILED", error)
    }
    if created { _ = try? await gateway.call("groups.disband", ["room_id": roomID], as: JSONValue.self) }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try? await store.delete(bot, via: gateway, urlSession: urlSession) }
    await store.reload(gateway)
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
}

if phases.contains("slash-raw") {
    let bot = try await crewTest()
    let resumed = try await gateway.call("session.resume", ["session_id": bot.canonicalSession?.id.rawValue ?? "", "profile": "crew-test"], as: JSONValue.self)
    guard case .object(let snapshot) = resumed, case .string(let runtime) = snapshot["session_id"] else { print("no runtime"); exit(1) }
    print("runtime", runtime, "stored", snapshot["stored_session_id"] ?? .null, "count", snapshot["message_count"] ?? .null)
    var recorded: [String: JSONValue] = [:]
    for command in (env["SLASH"] ?? "/status").split(separator: ",") {
        do {
            let result = try await gateway.call("slash.exec", ["session_id": runtime, "command": String(command)], as: JSONValue.self)
            recorded[String(command)] = result
            print("SLASH", command, String(decoding: try encoder.encode(result), as: UTF8.self).prefix(400))
        } catch {
            if case GatewayError.rpc(let code, let message) = error { recorded[String(command)] = .object(["error": .object(["code": .number(Double(code)), "message": .string(message)])]) }
            print("SLASH", command, "ERROR", error)
        }
    }
    if env["RECORD"] != nil {
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let file = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/slash.exec.v0.22.5.json").standardized
        try (pretty.encode(JSONValue.object(recorded)) + Data("\n".utf8)).write(to: file)
        print("RECORDED", file.lastPathComponent, recorded.count)
    }
    if env["COMPRESS"] != nil {
        let started = Date.now
        do {
            let result = try await gateway.call("session.compress", ["session_id": runtime], as: JSONValue.self, timeout: .seconds(240))
            guard case .object(var object) = result else { throw HermesError.invalidResponse }
            object["messages"] = nil
            object["info"] = nil
            object["usage"] = nil
            print("COMPRESS", Date.now.timeIntervalSince(started), String(decoding: try encoder.encode(JSONValue.object(object)), as: UTF8.self).prefix(1500))
        } catch {
            print("COMPRESS", Date.now.timeIntervalSince(started), "ERROR", error)
        }
    }
    if let skill = env["SKILL"] {
        do {
            let result = try await gateway.call("command.dispatch", ["session_id": runtime, "name": skill, "arg": env["ARG"] ?? ""], as: JSONValue.self)
            print("DISPATCH", skill, String(decoding: try encoder.encode(result), as: UTF8.self).prefix(600))
            if env["SUBMIT"] != nil, case .object(let directive) = result, case .string(let message) = directive["message"] {
                _ = try await gateway.call("prompt.submit", ["session_id": runtime, "text": message], as: JSONValue.self)
                try await Task.sleep(for: .seconds(Double(env["SUBMIT"] ?? "") ?? 60))
                let stored = bot.canonicalSession?.resolvedID ?? StoredSessionID(rawValue: "")
                let (data, _) = try await urlSession.data(for: historyRequest(of: stored, profile: "crew-test", on: server, limit: 8))
                guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { throw HermesError.invalidResponse }
                let pretty = JSONEncoder()
                pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let file = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/skill-invocation.history.json").standardized
                try (pretty.encode(JSONValue.array(messages)) + Data("\n".utf8)).write(to: file)
                print("RECORDED", file.lastPathComponent, messages.count)
            }
        } catch {
            print("DISPATCH", skill, "ERROR", error)
        }
    }
    let after = try await gateway.call("session.resume", ["session_id": bot.canonicalSession?.id.rawValue ?? "", "profile": "crew-test"], as: JSONValue.self)
    if case .object(let snapshot) = after { print("after runtime", snapshot["session_id"] ?? .null, "stored", snapshot["stored_session_id"] ?? .null, "count", snapshot["message_count"] ?? .null) }
    exit(0)
}

let bot = try await crewTest()
print("canonical", bot.canonicalSession?.id.rawValue ?? "nil")
let chat = try await attached(bot)
show("attach", chat)

if phases.contains("new-chat") {
    let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/scenarios/start-new-chat").standardized
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user")].filter { $0.0.count > 2 }
    func save(_ file: String, _ value: JSONValue) throws {
        let text = scrubs.reduce(String(decoding: try pretty.encode(value), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }.replacing(/\/opt\/data\/[^\s"'\\]*/, with: "/opt/hermes/data")
        try Data((text + "\n").utf8).write(to: folder.appending(path: "\(file).json"))
        print("RECORDED \(file).json")
    }
    func roster() async throws -> JSONValue {
        let raw = try await gateway.call("profiles.list", ["include_sessions": true], as: JSONValue.self)
        guard case .object(let object) = raw, case .array(let profiles) = object["profiles"] else { return .object(["profiles": .array([])]) }
        return .object(["profiles": .array(profiles.filter { if case .object(let profile) = $0, case .string("crew-test") = profile["name"] { true } else { false } })])
    }
    let old = bot.canonicalSession?.id.rawValue ?? ""
    try save("profiles.before", try await roster())
    try await chat.startNewChat()
    show("after new chat", chat)
    try save("profiles.retired", try await roster())
    chat.send("Reply with just: fresh-start", mode: .send)
    try await waitIdle(chat)
    show("after reply", chat)
    try await Task.sleep(for: .seconds(2))
    try save("profiles.after", try await roster())
    let fresh = try await crewTest()
    print("canonical after", fresh.canonicalSession?.id.rawValue ?? "nil", "preview", fresh.canonicalSession?.preview ?? "nil")
    var listing = hermesRequest("api/sessions", on: server)
    listing.url?.append(queryItems: [URLQueryItem(name: "profile", value: "crew-test"), URLQueryItem(name: "order", value: "recent"), URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "archived", value: "include")])
    let ids = [old, fresh.canonicalSession?.id.rawValue ?? ""]
    guard case .object(let page) = try await fetch(listing, with: urlSession, as: JSONValue.self), case .array(let rows) = page["sessions"] else { exit(1) }
    let kept = rows.filter { if case .object(let row) = $0, case .string(let id) = row["id"] { ids.contains(id) } else { false } }
    for case .object(let row) in kept { print("ROW", row["id"] ?? .null, row["title"] ?? .null, "archived", row["archived"] ?? .null, "hidden", row["hidden"] ?? .null) }
    if let session = fresh.canonicalSession, case .object(let history) = try await fetch(historyRequest(of: session.resolvedID, profile: "crew-test", on: server, limit: 20), with: urlSession, as: JSONValue.self) {
        try save("crew-test.preview", history["messages"] ?? .array([]))
    }
    exit(0)
}

if phases.contains("slash-run") {
    func local(_ chat: ChatSession) -> String {
        chat.transcript.turns.filter(\.isCommand).map { "\($0.notice ?? "") -> \($0.finishedAt == nil ? "running" : $0.failure.map { "!\($0)" } ?? ($0.output ?? "<no output>").prefix(80).replacingOccurrences(of: "\n", with: " | "))" }.joined(separator: "\n   ")
    }
    print("catalog", chat.slashCommands.count)
    for line in (env["SLASH_LINES"] ?? "/status").components(separatedBy: ";;") {
        let before = chat.transcript.turns.filter { !$0.isCommand }.count
        chat.send(line, mode: .send)
        try await Task.sleep(for: .seconds(1))
        try await waitIdle(chat, until: { chat in !chat.isRunning && chat.transcript.waiting.isEmpty && chat.transcript.turns.allSatisfy { !$0.isCommand || $0.finishedAt != nil } })
        print("== \(line): turns \(before) -> \(chat.transcript.turns.filter { !$0.isCommand }.count), returned \(chat.returned.map { String($0.prefix(60)) }), failure \(chat.failure ?? "-")")
        print("   " + local(chat))
        for summary in summary(chat.transcript).suffix(2) { print("  ", summary) }
        chat.returned = []
    }
    exit(0)
}

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

if phases.contains("screenshot") {
    record("screenshot-turn")
    chat.send("Use your browser_exec tool to open https://example.com and take a screenshot of the page, then tell me in one short sentence what the heading says.", mode: .send)
    try await waitIdle(chat)
    show("screenshot live", chat)
    let reloaded = try await attached(try await crewTest())
    if let stored = try await crewTest().canonicalSession?.resolvedID {
        let (data, _) = try await urlSession.data(for: historyRequest(of: stored, profile: "crew-test", on: server, limit: 8))
        try data.write(to: outDir.appending(path: "screenshot.history.json"))
    }
    for (label, session) in [("LIVE", chat), ("HISTORY", reloaded)] {
        for item in session.transcript.turns.last?.work ?? [] {
            guard case .tool(let call) = item.kind, let image = call.image else { continue }
            print(label, "IMAGE", image.name, "bytes", (try? await session.download(image))?.count ?? -1)
        }
    }
}

if phases.contains("compressed") {
    record("compressed-turn")
    for round in 1...2 {
        chat.send("Reply with one short sentence about the number \(round).", mode: .send)
        try await waitIdle(chat)
        print("COMPACT", round, (try? await chat.compact()) ?? "nil")
    }
    chat.send("Reply with just: hi", mode: .send)
    var seen: [String] = []
    while chat.isRunning || seen.isEmpty {
        if let line = chat.statusLine, seen.last != line { seen.append(line); print("COMPRESSED statusLine:", line) }
        if !chat.isRunning, chat.transcript.turns.last?.reply == "hi" { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    try await waitIdle(chat)
    show("compressed live", chat)
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

if phases.contains("a2ui-update") {
    let skill = try String(contentsOf: URL(fileURLWithPath: #filePath).appending(path: "../../../Sources/Profile/crew-ui.SKILL.md").standardized, encoding: .utf8)
    var install = hermesRequest("api/skills/content", on: server, json: ["name": "crew-ui", "content": skill, "profile": "crew-test"])
    install.httpMethod = "PUT"
    _ = try await fetch(install, with: urlSession, as: JSONValue.self)
    let name = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let store = BotStore(fixture: [], statuses: [:])
    Task { await store.run(gateway, urlSession: urlSession) }
    try await Task.sleep(for: .seconds(3))
    do {
        try await store.create(NewProfile(name: name, description: "Crew card probe", soul: nil, cloneFrom: "crew-test"), via: gateway) { $0.title = "Crew Cards" }
        await store.reload(gateway)
        guard let fresh = store.bots.first(where: { $0.name == name }) else { throw HermesError.invalidResponse }
        let described = try await gateway.call("profiles.describe", ["name": name], as: JSONValue.self)
        print("A2UI-UPDATE skill", String(decoding: try encoder.encode(described), as: UTF8.self).firstMatch(of: /\{[^{}]*"crew-ui"[^{}]*\}/).map { String($0.0) } ?? "crew-ui missing")
        let chat = try await attached(fresh)
        func surfaceIds(_ reply: String) -> [String] { reply.matches(of: /"surfaceId"\s*:\s*"([^"]+)"/).map { String($0.1) } }
        func turn(_ text: String) async throws {
            chat.send(text, mode: .send)
            try await Task.sleep(for: .seconds(2))
            try await waitIdle(chat)
            let reply = chat.transcript.turns.last?.reply ?? ""
            print("A2UI-UPDATE", text, "| ids", surfaceIds(reply), "| creates", reply.matches(of: /createSurface/).count, "| chars", reply.count)
        }
        try await turn(env["A2UI_PROMPT"] ?? "Give me a recipe for köttbullar for 4")
        try await turn("Make it for 6")
        try await turn("Tick off the onion and the breadcrumbs on the card, I already have them.")
        try await turn("Also give me a vegan version, I want to keep this one too")
        try await Task.sleep(for: .seconds(3))
        await store.reload(gateway)
        guard let session = store.bots.first(where: { $0.name == name })?.canonicalSession else { throw HermesError.invalidResponse }
        let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: name, on: server, limit: 200))
        guard case .object(let page) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let messages) = page["messages"] else { throw HermesError.invalidResponse }
        let keys: Set = ["id", "role", "content", "tool_call_id", "tool_calls", "timestamp", "reasoning", "reasoning_content", "display_kind"]
        let kept = messages.map { row in if case .object(let object) = row { JSONValue.object(object.filter { keys.contains($0.key) }) } else { row } }
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let scrubs = [(server.host() ?? "", "hermes.example.com"), (name, "crew-test-peer")].filter { $0.0.count > 2 }
        let text = scrubs.reduce(String(decoding: try pretty.encode(JSONValue.object(["messages": .array(kept)])), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }.replacingOccurrences(of: "/opt/data/", with: "/opt/hermes/data/")
        let file = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/chat.a2ui-update.history.json").standardized
        try Data((text + "\n").utf8).write(to: file)
        print("RECORDED \(kept.count) rows to \(file.path)")
    } catch {
        print("A2UI-UPDATE FAILED", error)
    }
    await store.reload(gateway)
    if let bot = store.bots.first(where: { $0.name == name }) { try await store.delete(bot, via: gateway, urlSession: urlSession) }
    print(store.bots.contains { $0.name == name } ? "THROWAWAY NOT DELETED: \(name)" : "throwaway deleted")
    exit(0)
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
            peerChats.open(peer, seed: nil, on: gateway, urlSession: urlSession)
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

if phases.contains("open-timing") {
    nonisolated struct Page: Decodable, Sendable { let messages: [HistoryRow] }
    let clock = ContinuousClock()
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let bots = try await gateway.call("profiles.list", ["include_sessions": true], as: BotRoster.self).profiles
    print("bot | rows | KB | GET 500 ms | decode ms | Transcript ms | visible ms | turns | GET 20 ms | page KB | GET page ms | page Transcript ms | page turns")
    for bot in bots {
        guard let session = bot.canonicalSession else { continue }
        let start = clock.now
        let (data, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: bot.name, on: server, limit: 500))
        let fetched = clock.now
        let rows = try decoder.decode(Page.self, from: data).messages
        let decoded = clock.now
        let transcript = Transcript(history: rows)
        let built = clock.now
        let visible = transcript.visible
        let shown = clock.now
        _ = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: bot.name, on: server, limit: 20))
        let preview = clock.now
        let (pageData, _) = try await urlSession.data(for: historyRequest(of: session.resolvedID, profile: bot.name, on: server, limit: BotStore.pageRows))
        let paged = clock.now
        let page = Transcript(window: try decoder.decode(Page.self, from: pageData).messages)
        let pageBuilt = clock.now
        let ms = { (duration: Duration) in String(format: "%.0f", Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000) }
        print("\(bot.title) | \(rows.count) | \(data.count / 1024) | \(ms(fetched - start)) | \(ms(decoded - fetched)) | \(ms(built - decoded)) | \(ms(shown - built)) | \(visible.turns.count) | \(ms(preview - shown)) | \(pageData.count / 1024) | \(ms(paged - preview)) | \(ms(pageBuilt - paged)) | \(page.visible.turns.count)")
    }
    for bot in bots {
        guard let session = bot.canonicalSession else { continue }
        func page(_ limit: Int, _ offset: Int) async throws -> [Int] {
            var request = historyRequest(of: session.resolvedID, profile: bot.name, on: server, limit: limit)
            request.url?.append(queryItems: [URLQueryItem(name: "offset", value: String(offset))])
            return try await fetch(request, with: urlSession, as: Page.self).messages.map(\.id)
        }
        let whole = try await page(500, 0)
        var paged: [Int] = []
        for offset in stride(from: 0, to: 600, by: 100) { paged += try await page(100, offset) }
        let first = try await page(100, 0)
        print("paging \(bot.title): whole \(whole.count), paged \(paged.count), same set \(Set(whole) == Set(paged.prefix(500))), page order \(first.first ?? 0)...\(first.last ?? 0), whole order \(whole.first ?? 0)...\(whole.last ?? 0), unique \(Set(paged).count)")
    }
    let bot = try await crewTest()
    for attempt in 1...3 {
        let start = clock.now
        let (_, snapshot) = try await openBotChat(bot.canonicalSession?.id, profile: bot.name, via: gateway)
        let resumed = clock.now
        _ = try await gateway.eventsSince(snapshot.sessionID, after: 0)
        let replayed = clock.now
        print("crew-test attach \(attempt): session.resume \(resumed - start), events.since \(replayed - resumed)")
        _ = try? await gateway.call("session.close", ["session_id": snapshot.sessionID.rawValue], as: JSONValue.self)
        let closed = clock.now
        let (_, cold) = try await openBotChat(bot.canonicalSession?.id, profile: bot.name, via: gateway)
        print("crew-test cold attach \(attempt): session.resume after close \(clock.now - closed), running \(cold.running ?? false)")
    }
    let chat = ChatSession(bot: bot, gateway: gateway, urlSession: urlSession)
    let start = clock.now
    Task { await chat.run() }
    while chat.transcript.turns.isEmpty, chat.failure == nil, clock.now - start < .seconds(20) { try await Task.sleep(for: .milliseconds(5)) }
    print("crew-test ChatSession first transcript after \(clock.now - start) (\(chat.visible.turns.count) turns)")
    let (pageData, _) = try await urlSession.data(for: historyRequest(of: bot.canonicalSession!.resolvedID, profile: bot.name, on: server, limit: BotStore.pageRows))
    let seed = Transcript(window: try decoder.decode(Page.self, from: pageData).messages)
    let seededStart = clock.now
    let seeded = ChatSession(bot: bot, seed: seed, gateway: gateway, urlSession: urlSession)
    print("crew-test seeded ChatSession shows \(seeded.visible.turns.count) turns after \(clock.now - seededStart)")
    Task { await seeded.run() }
    seeded.send("Reply with just: early", mode: .send)
    print("sent before attach: waiting \(seeded.transcript.waiting.map { $0.pending.map { "\($0)" } ?? "-" })")
    try await Task.sleep(for: .seconds(2))
    try await waitIdle(seeded)
    show("seeded, sent before attach", seeded)
}

if phases.contains("pages") {
    let clock = ContinuousClock()
    let ms = { (duration: Duration) in String(format: "%.0f", Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000) }
    let ids = { (transcript: Transcript) in transcript.visible.turns.map(\.id) }
    let bots = try await gateway.call("profiles.list", ["include_sessions": true], as: BotRoster.self).profiles
    print("bot | same ids | rows | pages | latest page ms | older page ms | window mismatches")
    for bot in bots {
        guard let session = bot.canonicalSession else { continue }
        var pages = HistoryPages()
        var start = clock.now
        pages.merge(latest: try await history(of: session.resolvedID, profile: bot.name, on: server, with: urlSession, limit: BotStore.pageRows))
        let latest = clock.now - start
        var shown = [ids(pages.transcript)]
        var older: [Duration] = []
        while !pages.reachedStart {
            start = clock.now
            pages.prepend(older: try await history(of: session.resolvedID, profile: bot.name, on: server, with: urlSession, limit: BotStore.pageRows, offset: pages.rows.count))
            older.append(clock.now - start)
            shown.append(ids(pages.transcript))
        }
        let whole = ids(Transcript(history: pages.rows))
        let mismatches = shown.filter { Array(whole.suffix($0.count)) != $0 }.count
        let slowest = older.max().map(ms) ?? "-"
        print("\(bot.title) | \(session.id == session.resolvedID) | \(pages.rows.count) | \(shown.count) | \(ms(latest)) | \(slowest) | \(mismatches)")
    }
    for bot in bots.filter({ ($0.canonicalSession?.messageCount ?? 0) > BotStore.pageRows }) {
        let chat = ChatSession(bot: bot, resuming: bot.canonicalSession?.resolvedID, gateway: gateway, urlSession: urlSession)
        chat.sync(to: bot.canonicalSession?.position)
        for _ in 0..<500 where chat.visible.turns.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let first = chat.visible.turns.count
        var loads = 0
        while chat.earlier != .complete, loads < 30 {
            chat.loadEarlier()
            loads += 1
            while chat.earlier == .loading { try await Task.sleep(for: .milliseconds(20)) }
            if chat.earlier == .failed { break }
        }
        print("ChatSession \(bot.title): latest page \(first) turns, \(loads) older loads, \(chat.visible.turns.count) turns, state \(chat.earlier)")
    }
}

if phases.contains("history") {
    let reloaded = try await attached(try await crewTest())
    print("== full history")
    for line in summary(reloaded.transcript) { print("  ", line) }
}

eventLog = nil
await gateway.disconnect()
exit(0)
