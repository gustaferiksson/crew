import Foundation
import Observation

nonisolated struct RoutineJob: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let title: String
    let owner: String?
    let prompt: String
    let schedule: String
    let nextRun: Date?
    let lastRun: Date?
    let lastStatus: String?
    let issue: String?
    let isPaused: Bool
}

nonisolated extension RoutineJob: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, schedule, enabled, state
        case id = "job_id"
        case prompt = "prompt_preview"
        case nextRun = "next_run_at"
        case lastRun = "last_run_at"
        case lastStatus = "last_status"
        case lastFireError = "last_fire_error"
        case lastDeliveryError = "last_delivery_error"
        case lastError = "last_error"
        case pausedReason = "paused_reason"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        let tag = name.wholeMatch(of: /\[bot:([A-Za-z0-9][A-Za-z0-9_-]*)\]\s*(.*)/)
        owner = tag.map { String($0.1).lowercased() }
        title = tag.map { String($0.2) } ?? name
        prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
        schedule = (try? container.decodeIfPresent(String.self, forKey: .schedule)) ?? ""
        nextRun = (try? container.decodeIfPresent(String.self, forKey: .nextRun)).flatMap { try? Date($0, strategy: .iso8601) }
        lastRun = (try? container.decodeIfPresent(String.self, forKey: .lastRun)).flatMap { try? Date($0, strategy: .iso8601) }
        lastStatus = try? container.decodeIfPresent(String.self, forKey: .lastStatus)
        issue = [CodingKeys.lastFireError, .lastDeliveryError, .lastError, .pausedReason]
            .compactMap { try? container.decodeIfPresent(String.self, forKey: $0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        isPaused = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) == false
            || (try? container.decodeIfPresent(String.self, forKey: .state)) == "paused"
    }
}

nonisolated private struct CronParams: Encodable {
    let action: String
    let profile: String
    var name: String?
    var schedule: String?
    var prompt: String?
    var includeDisabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case action, profile, name, schedule, prompt
        case includeDisabled = "include_disabled"
    }
}

nonisolated private struct CronReply: Decodable {
    let success: Bool?
    let error: String?
    let jobs: [RoutineJob]?
    let scoped: String?
}

private struct CronContext {
    let profile: String
    let gateway: Gateway
    let urlSession: URLSession
}

nonisolated private struct RoutineError: LocalizedError {
    let errorDescription: String?
}

@Observable
final class RoutineStore {
    private(set) var jobs: [RoutineJob]
    private(set) var isLoaded: Bool
    private(set) var loadError: String?
    private(set) var inFlight: Set<RoutineJob.ID> = []
    var failure: String?

    private var context: CronContext?

    init() {
        jobs = []
        isLoaded = false
    }

    init(fixture jobs: [RoutineJob]) {
        self.jobs = jobs
        isLoaded = true
    }

    func run(profile: String, gateway: Gateway, urlSession: URLSession) async {
        if context?.profile != profile {
            jobs = []
            isLoaded = false
            loadError = nil
        }
        context = CronContext(profile: profile, gateway: gateway, urlSession: urlSession)
        let events = gateway.events()
        await reload()
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await event in events where ["cron.changed", "gateway.ready"].contains(event.type) {
                    await self.reload()
                }
            }
            group.addTask {
                while (try? await Task.sleep(for: .seconds(20))) != nil {
                    await self.reload()
                }
            }
        }
    }

    func toggle(_ job: RoutineJob) async {
        await perform(job) { context in
            _ = try await self.manage(CronParams(action: job.isPaused ? "resume" : "pause", profile: context.profile, name: job.id), on: context.gateway)
        }
    }

    func delete(_ job: RoutineJob) async {
        await perform(job) { context in
            _ = try await self.manage(CronParams(action: "remove", profile: context.profile, name: job.id), on: context.gateway)
        }
    }

    func trigger(_ job: RoutineJob) async {
        await perform(job) { context in
            var request = hermesRequest("api/cron/jobs/\(job.id)/trigger", on: context.gateway.server, json: [:])
            request.url?.append(queryItems: [URLQueryItem(name: "profile", value: context.profile)])
            _ = try await fetch(request, with: context.urlSession, as: JSONValue.self)
        }
    }

    func create(title: String, prompt: String, schedule: String) async throws {
        guard let context else { throw RoutineError(errorDescription: String(localized: "Crew isn't connected to the server.")) }
        do {
            let params = CronParams(action: "add", profile: context.profile, name: "[bot:\(context.profile)] \(title)", schedule: schedule, prompt: prompt)
            _ = try await manage(params, on: context.gateway)
        } catch {
            throw RoutineError(errorDescription: describe(error))
        }
        await reload()
    }

    private func reload() async {
        guard let context else { return }
        do {
            let reply = try await manage(CronParams(action: "list", profile: context.profile, includeDisabled: true), on: context.gateway)
            jobs = (reply.jobs ?? []).filter { reply.scoped == context.profile || $0.owner == context.profile.lowercased() }
            isLoaded = true
            loadError = nil
        } catch {
            loadError = describe(error)
        }
    }

    private func perform(_ job: RoutineJob, _ action: (CronContext) async throws -> Void) async {
        guard let context, !inFlight.contains(job.id) else { return }
        inFlight.insert(job.id)
        do {
            try await action(context)
        } catch {
            failure = describe(error)
        }
        await reload()
        inFlight.remove(job.id)
    }

    private func manage(_ params: CronParams, on gateway: Gateway) async throws -> CronReply {
        let reply = try await gateway.call("cron.manage", params, as: CronReply.self)
        guard reply.success != false, reply.error == nil else {
            throw RoutineError(errorDescription: reply.error ?? String(localized: "The server couldn't update this routine."))
        }
        return reply
    }

    private func describe(_ error: any Error) -> String {
        if case GatewayError.rpc(_, let message) = error { return message }
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return String(localized: "Crew couldn't reach the server.")
    }
}

nonisolated func describeSchedule(_ raw: String) -> String {
    let schedule = raw.trimmingCharacters(in: .whitespaces)
    if let match = schedule.wholeMatch(of: /every (\d+)m/), let minutes = Int(match.1) {
        if minutes == 1440 { return String(localized: "Every day") }
        if minutes % 1440 == 0 { return String(localized: "Every \(minutes / 1440) days") }
        if minutes == 60 { return String(localized: "Every hour") }
        if minutes % 60 == 0 { return String(localized: "Every \(minutes / 60) hours") }
        return String(localized: "Every \(minutes) minutes")
    }
    let fields = schedule.split(separator: " ").map(String.init)
    guard fields.count == 5, let minute = Int(fields[0]), (0..<60).contains(minute) else {
        return schedule.prefix(1).uppercased() + schedule.dropFirst()
    }
    if fields[1...] == ["*", "*", "*", "*"] {
        return String(localized: "Every hour at :\(String(format: "%02d", minute))")
    }
    guard let hour = Int(fields[1]), (0..<24).contains(hour),
          let time = Calendar.current.date(from: DateComponents(hour: hour, minute: minute))?.formatted(date: .omitted, time: .shortened)
    else { return schedule }
    if fields[2...] == ["*", "*", "*"] { return String(localized: "Every day at \(time)") }
    if fields[2...] == ["*", "*", "1-5"] { return String(localized: "Weekdays at \(time)") }
    if fields[2...3] == ["*", "*"], let weekday = Int(fields[4]), (0...7).contains(weekday) {
        return String(localized: "Every \(Calendar.current.weekdaySymbols[weekday % 7]) at \(time)")
    }
    if let day = Int(fields[2]), fields[3...] == ["*", "*"] { return String(localized: "Monthly on day \(day) at \(time)") }
    return schedule
}
