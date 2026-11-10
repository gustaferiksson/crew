import Foundation

nonisolated struct Ticket: Decodable, Sendable { let ticket: String }

let env = ProcessInfo.processInfo.environment
let server = try serverURL(from: env["HERMES_URL"] ?? "")
let configuration = URLSessionConfiguration.ephemeral
configuration.timeoutIntervalForRequest = 10
let urlSession = URLSession(configuration: configuration)
_ = try await probe(server, with: urlSession)
_ = try await fetch(hermesRequest("auth/password-login", on: server, json: ["provider": "basic", "username": env["HERMES_USER"] ?? "", "password": env["HERMES_PASSWORD"] ?? ""]), with: urlSession, as: Empty.self)
let gateway = Gateway(server: server, urlSession: urlSession) {
    try await fetch(hermesRequest("api/auth/ws-ticket", on: server, json: [:]), with: urlSession, as: Ticket.self).ticket
}
await gateway.connect()
for _ in 0..<40 where await gateway.status != .connected { try await Task.sleep(for: .milliseconds(250)) }
guard await gateway.status == .connected else { print("not connected"); exit(1) }

let folder = URL(fileURLWithPath: #filePath).appending(path: "../../fixtures/scenarios/routine-stop").standardized
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let pretty = JSONEncoder()
pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let jobKeys: Set = ["id", "name", "prompt", "schedule_display", "next_run_at", "last_run_at", "last_status", "last_error", "last_delivery_error", "last_fire_error", "paused_reason", "enabled", "state", "latest_execution", "live_execution"]
let runKeys: Set = ["id", "status", "error", "claimed_at", "finished_at", "scheduled_instant"]
let started = Date.now
var failures: [String] = []

func log(_ text: String) {
    print(String(format: "+%5.1fs ", Date.now.timeIntervalSince(started)) + text)
}

func check(_ condition: Bool, _ label: String) {
    log((condition ? "ok   " : "FAIL ") + label)
    if !condition { failures.append(label) }
}

func trimmed(_ value: JSONValue, to keys: Set<String>) -> JSONValue {
    guard case .object(let object) = value else { return value }
    return .object(object.filter { keys.contains($0.key) }.mapValues { field in
        if case .object = field { return trimmed(field, to: runKeys) }
        return field
    })
}

func save(_ file: String, _ value: JSONValue) throws {
    try Data((String(decoding: try pretty.encode(value), as: UTF8.self) + "\n").utf8).write(to: folder.appending(path: "\(file).json"))
    log("recorded \(file).json")
}

func cron(_ path: String, method: String = "GET") -> URLRequest {
    var request = hermesRequest("api/cron/jobs\(path)", on: server, json: method == "POST" ? [:] : nil)
    request.httpMethod = method
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: "crew-test")])
    return request
}

func rawJob(_ id: String) async throws -> JSONValue? {
    guard case .array(let all) = try await fetch(cron(""), with: urlSession, as: JSONValue.self) else { return nil }
    return all.first { if case .object(let job) = $0, case .string(id) = job["id"] { true } else { false } }.map { trimmed($0, to: jobKeys) }
}

func decoded(_ raw: JSONValue?) throws -> RoutineJob? {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try raw.map { try decoder.decode(RoutineJob.self, from: JSONEncoder().encode($0)) }
}

func add(_ title: String, every schedule: String) async throws -> String {
    let added = try await gateway.call("cron.manage", [
        "action": .string("add"), "profile": .string("crew-test"), "name": .string("[bot:crew-test] \(title)"), "schedule": .string(schedule),
        "prompt": .string("First call the terminal tool in the foreground with the command `sleep 150` and timeout 200. Then write a 2000-word story about a lighthouse keeper and reply with it."),
    ] as [String: JSONValue], as: JSONValue.self)
    guard case .object(let reply) = added, case .string(let id) = reply["job_id"] else { throw HermesError.invalidResponse }
    log("added \(title) \(id)")
    return id
}

func waitFor(_ seconds: Double, _ condition: () async throws -> Bool) async throws -> Bool {
    let deadline = Date.now.addingTimeInterval(seconds)
    while Date.now < deadline {
        if try await condition() { return true }
        try await Task.sleep(for: .milliseconds(500))
    }
    return false
}

func plainJSON(_ path: String) async throws -> [String: JSONValue] {
    var request = hermesRequest(path, on: server)
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: "crew-test"), URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "archived", value: "include")])
    let (data, _) = try await urlSession.data(for: request)
    guard case .object(let object) = try JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
    return object
}

func probeRunSessions(_ titles: [String] = ["Long check", "Minute check"]) async throws -> [(id: String, ended: Bool)] {
    guard case .array(let sessions) = try await plainJSON("api/sessions")["sessions"] else { return [] }
    return sessions.compactMap { session in
        guard case .object(let row) = session, case .string("cron") = row["source"], case .string(let title) = row["title"], case .string(let id) = row["id"],
              titles.contains(where: { title.hasPrefix("[bot:crew-test] \($0) · ") })
        else { return nil }
        if case .number = row["ended_at"] { return (id, true) }
        return (id, false)
    }
}

let store = RoutineStore()
let cleanupOnly = CommandLine.arguments.contains("--cleanup")
var created: [String] = CommandLine.arguments.dropFirst().filter { $0 != "--cleanup" }

if !cleanupOnly {
    Task { await store.run(profile: "crew-test", gateway: gateway, urlSession: urlSession) }

    do {
        let id = try await add("Long check", every: "every 1440m")
        created.append(id)
        _ = try await waitFor(30) { store.jobs.contains { $0.id == id } }
        try save("jobs.idle", try await rawJob(id) ?? .null)
        guard let job = store.jobs.first(where: { $0.id == id }) else { throw HermesError.invalidResponse }
        check(!store.isRunning(job) && job.tracksRuns, "idle routine is not running")

        let trigger = Task {
            await store.trigger(job)
            log("Run Now returned")
        }
        try await Task.sleep(for: .milliseconds(300))
        check(store.isRunning(job), "Run Now shows Running at once")
        try await Task.sleep(for: .seconds(12))
        try save("jobs.running", try await rawJob(id) ?? .null)
        check(try decoded(try await rawJob(id))?.liveRunID != nil, "server lists the live run")
        check(store.alert == nil, "no alert after the 10 s idle timeout while the run is live")
        check(store.isRunning(store.jobs.first { $0.id == id } ?? job), "still Running past 10 s")

        await store.stop(store.jobs.first { $0.id == id } ?? job)
        let stopped = store.jobs.first { $0.id == id }
        try save("jobs.stopped", try await rawJob(id) ?? .null)
        check(store.alert == nil, "Stop raised no alert")
        check(stopped?.lastStatus == "cancelled", "row shows Stopped")
        check(stopped.map { !store.isRunning($0) } ?? false, "row no longer Running")
        await trigger.value
        check(store.alert == nil, "the returning Run Now raised no alert")
        if case .array(let runs) = try await plainJSON("api/cron/jobs/\(id)/runs")["runs"], case .object(let newest) = runs.first, case .string(let title) = newest["title"] {
            check(title.hasPrefix("CANCELLED"), "run history titles the stopped run \(title.prefix(40))")
        } else {
            check(false, "run history lists the stopped run")
        }

        if let stopped { await store.stop(stopped) }
        check(store.alert?.title == "Nothing Was Running", "second Stop says Nothing Was Running")
        store.alert = nil
        try save("cancel.idle", trimmed(try await fetch(cron("/\(id)/cancel", method: "POST"), with: urlSession, as: JSONValue.self), to: ["cancelled", "detail", "execution_id", "job_id", "success", "status"]))
    } catch {
        check(false, "run and stop flow threw \(error)")
    }

    do {
        let id = try await add("Minute check", every: "every 1m")
        created.append(id)
        check(try await waitFor(150) { try decoded(try await rawJob(id))?.liveRunID != nil }, "the scheduler starts the run on its own")
        try save("jobs.scheduled", try await rawJob(id) ?? .null)
        check(try await waitFor(25) { store.jobs.first { $0.id == id }.map(store.isRunning) ?? false }, "store shows the scheduler's run as Running")
        if let job = store.jobs.first(where: { $0.id == id }) { await store.toggle(job) }
        let paused = try decoded(try await rawJob(id))
        try save("jobs.paused-running", try await rawJob(id) ?? .null)
        check(paused?.isPaused == true && paused?.liveRunID != nil, "Pause leaves the live run going")
        if let job = store.jobs.first(where: { $0.id == id }) { await store.delete(job) }
        check(!store.jobs.contains { $0.id == id } && store.alert == nil, "Delete while running removes the row")
        check(try await waitFor(30) { try await probeRunSessions(["Minute check"]).contains { $0.ended } }, "Delete while running ends the run")
    } catch {
        check(false, "scheduler flow threw \(error)")
    }
}

for id in created {
    _ = try? await gateway.call("cron.manage", ["action": .string("remove"), "profile": .string("crew-test"), "name": .string(id)] as [String: JSONValue], as: JSONValue.self)
}
if case .array(let left) = try await fetch(cron(""), with: urlSession, as: JSONValue.self) {
    let names = left.compactMap { job -> String? in if case .object(let row) = job, case .string(let name) = row["name"] { name } else { nil } }
    check(!names.contains { $0.hasPrefix("[bot:crew-test] Long check") || $0.hasPrefix("[bot:crew-test] Minute check") }, "no probe routine left on crew-test")
}
try await Task.sleep(for: .seconds(5))
for session in ((try? await probeRunSessions()) ?? []).map(\.id) {
    let snapshot = (try? await plainJSON("api/sessions/\(session)/mutation-snapshot")) ?? [:]
    var request = hermesRequest("api/sessions/\(session)", on: server)
    request.httpMethod = "DELETE"
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: "crew-test"), URLQueryItem(name: "request_id", value: UUID().uuidString)])
    for key in ["revision", "generation"] {
        if case .number(let value) = snapshot["runtime_\(key)"] { request.url?.append(queryItems: [URLQueryItem(name: "expected_\(key)", value: String(Int(value)))]) }
    }
    let status = ((try? await urlSession.data(for: request))?.1 as? HTTPURLResponse)?.statusCode ?? 0
    log((200..<300).contains(status) ? "deleted run session \(session)" : "SESSION DELETE FAILED \(status) \(session) \(snapshot.keys.sorted())")
}
log(failures.isEmpty ? "ALL OK" : "FAILURES: \(failures.joined(separator: "; "))")
exit(failures.isEmpty ? 0 : 1)
