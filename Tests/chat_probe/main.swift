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
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
Task {
    for await event in gateway.events() {
        var object: [String: JSONValue] = ["type": .string(event.type), "payload": event.payload ?? .null]
        if let id = event.sessionID { object["session_id"] = .string(id.rawValue) }
        if let seq = event.seq { object["seq"] = .number(Double(seq)) }
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
        return "[\(turn.status.rawValue)] \(turn.prompt?.text.prefix(40) ?? "<no prompt>") | \(work.joined(separator: ", ")) | worked \(Int(worked))s | \(turn.reply.prefix(70).replacingOccurrences(of: "\n", with: " "))\(turn.failure.map { " !\($0)" } ?? "")"
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

func waitIdle(_ chat: ChatSession, timeout: Int = 300, until: (ChatSession) -> Bool = { !$0.isRunning && $0.queue.isEmpty }) async throws {
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

if phases.contains("interrupt") {
    record("interrupt-turn")
    chat.send("Use the terminal to run: sleep 40 && echo done. Then tell me the output.", mode: .send)
    try await waitIdle(chat, timeout: 60) { chat in
        chat.transcript.turns.last?.work.contains { if case .tool(let call) = $0.kind { call.status == .running } else { false } } ?? false
    }
    chat.send("this should be queued then dropped by stop", mode: .queue)
    print("queue before stop", chat.queue.count)
    chat.stop()
    try await waitIdle(chat, timeout: 60)
    show("interrupt", chat)
}

if phases.contains("queue") {
    record("queue-turn")
    chat.send("Use the terminal to run: sleep 5 && echo first. Reply with just the output.", mode: .send)
    try await Task.sleep(for: .seconds(2))
    chat.send("Reply with exactly: queued-ok", mode: .queue)
    print("queued", chat.queue)
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
    var writes = 0
    Task { for await _ in storeA.unreadCleared.stream { writes += 1 } }
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
    print("READ unread clears announced by A: \(writes)")
    await peerGateway.disconnect()
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
        print(chat.transcript.hides(turn) ? "HIDDEN " : "SHOWN  ", turn.prompt?.text ?? turn.notice ?? turn.delivery ?? "-", "|", turn.reply)
    }
}

if phases.contains("record") {
    let scenario = CommandLine.arguments.last ?? ""
    guard scenario == "bot-mention" else { print("unknown scenario \(scenario)"); exit(1) }
    let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/scenarios/\(scenario)").standardized
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let peerName = "crew-test-\(UUID().uuidString.prefix(6).lowercased())"
    let names = ["crew-test", peerName]
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let scrubs = [(server.host() ?? "", "hermes.example.com"), (env["HERMES_USER"] ?? "", "user"), (env["HERMES_PASSWORD"] ?? "", "***"), (peerName, "crew-test-peer")].filter { $0.0.count > 2 }
    func save(_ name: String, _ value: JSONValue) throws {
        let text = scrubs.reduce(String(decoding: try pretty.encode(value), as: UTF8.self)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
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
        return messages
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

        chat.send("@\(peerName) hi", mentioning: [peer], mode: .send)
        var duringSaved = false
        var quietSince: Date?
        let started = Date.now
        while Date.now.timeIntervalSince(started) < 300 {
            try await Task.sleep(for: .milliseconds(250))
            let current = try await roster()
            let active = try await live(of: current.bots)
            let inHiddenTurn = chat.isRunning && chat.transcript.turns.last.map(chat.transcript.hides) == true
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
        for turn in chat.transcript.turns.suffix(4) {
            print(chat.transcript.hides(turn) ? "HIDDEN " : "SHOWN  ", turn.prompt?.text ?? turn.delivery ?? "-", "|", turn.reply)
        }
    } catch {
        print("RECORD FAILED", error)
    }
    await store.reload(gateway)
    if let peer = store.bots.first(where: { $0.name == peerName }) { try await store.delete(peer, via: gateway, urlSession: urlSession) }
    print(store.bots.contains { $0.name == peerName } ? "PEER NOT DELETED" : "peer deleted")
}

if phases.contains("history") {
    let reloaded = try await attached(try await crewTest())
    print("== full history")
    for line in summary(reloaded.transcript) { print("  ", line) }
}

eventLog = nil
await gateway.disconnect()
exit(0)
