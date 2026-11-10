import Foundation
import Observation

nonisolated struct RoutineJob: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let title: String
    let prompt: String
    let schedule: String
    let nextRun: Date?
    let lastRun: Date?
    let lastStatus: String?
    let issue: String?
    let isPaused: Bool
    var missedRuns: Int?
    var latestRun: RoutineRun?
    var liveRunID: String?
    var tracksRuns = false
}

nonisolated struct RoutineRun: Decodable, Hashable, Sendable {
    let id: String
    let status: String
    let error: String?
    let claimedAt: Date?
    let finishedAt: Date?
    let scheduledInstant: Date?

    private enum CodingKeys: CodingKey {
        case id, status, error, claimedAt, finishedAt, scheduledInstant
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        claimedAt = (try? container.decodeIfPresent(String.self, forKey: .claimedAt)).flatMap { try? Date($0, strategy: .iso8601) }
        finishedAt = (try? container.decodeIfPresent(String.self, forKey: .finishedAt)).flatMap { try? Date($0, strategy: .iso8601) }
        scheduledInstant = (try? container.decodeIfPresent(String.self, forKey: .scheduledInstant)).flatMap { try? Date($0, strategy: .iso8601) }
    }
}

nonisolated private struct FireError: Decodable {
    let detail: String?
}

nonisolated extension RoutineJob: Decodable {
    private enum CodingKeys: CodingKey {
        case id, name, prompt, enabled, state, scheduleDisplay, nextRunAt, lastRunAt, lastStatus
        case lastFireError, lastDeliveryError, lastError, pausedReason, latestExecution, liveExecution
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        title = name.wholeMatch(of: /\[bot:[A-Za-z0-9][A-Za-z0-9_-]*\]\s*(.*)/).map { String($0.1) } ?? name
        prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
        schedule = (try? container.decodeIfPresent(String.self, forKey: .scheduleDisplay)) ?? ""
        nextRun = (try? container.decodeIfPresent(String.self, forKey: .nextRunAt)).flatMap { try? Date($0, strategy: .iso8601) }
        let fireError = (try? container.decodeIfPresent(String.self, forKey: .lastFireError))
            ?? (try? container.decodeIfPresent(FireError.self, forKey: .lastFireError))?.detail
        issue = ([fireError] + [CodingKeys.lastDeliveryError, .lastError, .pausedReason].map { try? container.decodeIfPresent(String.self, forKey: $0) })
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        isPaused = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) == false
            || (try? container.decodeIfPresent(String.self, forKey: .state)) == "paused"
        latestRun = try? container.decodeIfPresent(RoutineRun.self, forKey: .latestExecution)
        liveRunID = (try? container.decodeIfPresent(RoutineRun.self, forKey: .liveExecution))?.id
        tracksRuns = container.contains(.liveExecution)

        let ranAt = (try? container.decodeIfPresent(String.self, forKey: .lastRunAt)).flatMap { try? Date($0, strategy: .iso8601) }
        guard let missed = latestRun, missed.status == "missed", let finished = missed.finishedAt, ranAt.map({ finished > $0 }) ?? true else {
            lastRun = ranAt
            lastStatus = try? container.decodeIfPresent(String.self, forKey: .lastStatus)
            return
        }
        lastRun = missed.scheduledInstant ?? finished
        lastStatus = missed.status
        missedRuns = missed.error?.firstMatch(of: /×(\d+)/).flatMap { Int($0.1) } ?? 1
    }
}

nonisolated private struct CronParams: Encodable {
    let action: String
    let profile: String
    var name: String?
    var schedule: String?
    var prompt: String?
}

nonisolated private struct CronReply: Decodable {
    let success: Bool?
    let error: String?
}

nonisolated private struct CancelReply: Decodable {
    let cancelled: Bool
    let executionId: String?
}

nonisolated struct RoutineAlert: Hashable, Sendable {
    let title: String
    let message: String
}

private struct CronContext {
    let profile: String
    let gateway: Gateway
    let urlSession: URLSession

    func request(_ path: String, post: Bool = false) -> URLRequest {
        var request = hermesRequest("api/cron/jobs\(path)", on: gateway.server, json: post ? [:] : nil)
        request.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile)])
        return request
    }
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
    private(set) var stopping: Set<RoutineJob.ID> = []
    private var triggers: [RoutineJob.ID: Date] = [:]
    var alert: RoutineAlert?

    private var context: CronContext?

    init() {
        jobs = []
        isLoaded = false
    }

    init(fixture jobs: [RoutineJob], stopping: Set<RoutineJob.ID> = []) {
        self.jobs = jobs
        isLoaded = true
        self.stopping = stopping
        inFlight = stopping
    }

    func run(profile: String, gateway: Gateway, urlSession: URLSession) async {
        if context?.profile != profile {
            jobs = []
            isLoaded = false
            loadError = nil
            triggers = [:]
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

    func isRunning(_ job: RoutineJob) -> Bool {
        if job.liveRunID != nil { return true }
        guard job.tracksRuns, let tapped = triggers[job.id] else { return false }
        return !(job.latestRun?.claimedAt.map { $0 >= tapped.addingTimeInterval(-2) } ?? false)
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
        guard let context, triggers[job.id] == nil, !inFlight.contains(job.id) else { return }
        triggers[job.id] = .now
        var request = context.request("/\(job.id)/trigger", post: true)
        request.timeoutInterval = 7200
        let failure: (any Error)?
        do {
            _ = try await fetch(request, with: context.urlSession, as: JSONValue.self)
            failure = nil
        } catch {
            failure = error
        }
        guard self.context?.profile == context.profile else { return }
        await reload()
        triggers[job.id] = nil
        guard let failure, let current = jobs.first(where: { $0.id == job.id }), current.liveRunID == nil, current.lastRun == job.lastRun else { return }
        alert = RoutineAlert(title: String(localized: "Couldn't Update Routine"), message: describe(failure))
    }

    func stop(_ job: RoutineJob) async {
        guard !inFlight.contains(job.id) else { return }
        stopping.insert(job.id)
        await perform(job) { context in
            let reply = try await fetch(context.request("/\(job.id)/cancel", post: true), with: context.urlSession, as: CancelReply.self)
            guard reply.cancelled else {
                self.alert = RoutineAlert(title: String(localized: "Nothing Was Running"), message: String(localized: "\(job.title) had already finished."))
                return
            }
            for _ in 0..<30 {
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                await self.reload()
                guard self.context?.profile == context.profile, self.jobs.first(where: { $0.id == job.id })?.liveRunID == reply.executionId else { return }
            }
        }
        stopping.remove(job.id)
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
            let listed = try await fetch(context.request(""), with: context.urlSession, as: [RoutineJob].self)
            guard self.context?.profile == context.profile else { return }
            jobs = listed
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
            if self.context?.profile == context.profile {
                alert = RoutineAlert(title: String(localized: "Couldn't Update Routine"), message: describe(error))
            }
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
