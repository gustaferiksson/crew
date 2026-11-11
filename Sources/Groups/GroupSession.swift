import Foundation
import Observation

nonisolated struct RoomEvent: Decodable, Sendable, Equatable {
    struct Actor: Decodable, Sendable, Equatable {
        let profile: String?
        var id: String?
        var displayName: String?

        private enum CodingKeys: String, CodingKey {
            case profile, id
            case displayName = "display_name"
        }
    }

    struct Payload: Decodable, Sendable, Equatable {
        var text: String?
        var memberID: String?
        var error: String?
        var name: String?
        var threadID: String?
        var taskID: String?
        var status: String?
        var discussionEventID: String?
        var purpose: String?
        var notes: String?
        var routing: String?
        var leadMemberID: String?
        var memberIDs: [String]?
        var everyone: Bool?
        var fallback: Bool?

        var context: RoomContext {
            RoomContext(purpose: purpose ?? "", notes: notes ?? "", routing: routing ?? "everyone", leadMemberID: leadMemberID ?? "")
        }

        private enum CodingKeys: String, CodingKey {
            case text, error, name, status, purpose, notes, routing, everyone, fallback
            case memberID = "member_id"
            case threadID = "thread_id"
            case taskID = "task_id"
            case discussionEventID = "discussion_event_id"
            case leadMemberID = "lead_member_id"
            case memberIDs = "member_ids"
        }
    }

    let seq: Int
    let eventID: String
    let kind: String
    let actor: Actor
    let payload: Payload
    let createdAt: Date

    var routineTitle: String? {
        guard kind == "message.user", let id = actor.id, id.hasPrefix("cron:") || id.hasPrefix("cron-notice:") else { return nil }
        let name = actor.displayName ?? String(id.drop { $0 != ":" }.dropFirst())
        return name.wholeMatch(of: /\[bot:[A-Za-z0-9][A-Za-z0-9_-]*\]\s*(.*)/).map { String($0.1) } ?? name
    }

    var routineOwner: String? {
        actor.displayName?.firstMatch(of: /^\[bot:([A-Za-z0-9][A-Za-z0-9_-]*)\]/).map { String($0.1).lowercased() }
    }

    private enum CodingKeys: String, CodingKey {
        case seq, kind, actor, payload
        case eventID = "event_id"
        case createdAt = "created_at"
    }
}

nonisolated struct RoomAction: Decodable, Sendable {
    let kind: String
    let memberID: String?
    let taskID: String?
    let executionGeneration: Int?
    let requestID: String?
    let approval: ApprovalParams?

    private enum CodingKeys: String, CodingKey {
        case kind, approval
        case memberID = "member_id"
        case taskID = "task_id"
        case executionGeneration = "execution_generation"
        case requestID = "request_id"
    }
}

nonisolated struct RoomState: Decodable, Sendable {
    struct Activity: Decodable, Sendable {
        let memberID: String
        let status: String
        var startedAt: Date?
        var tool: String?

        private enum CodingKeys: String, CodingKey {
            case status, tool
            case memberID = "member_id"
            case startedAt = "started_at"
        }
    }

    struct Driver: Decodable, Sendable {
        var working = false
        var pendingActions: [RoomAction] = []
        var memberActivity: [Activity]?
        var lastError: String?
        var maxContinues: Int?
        var routingModes: [String]?

        private enum CodingKeys: String, CodingKey {
            case working
            case pendingActions = "pending_actions"
            case memberActivity = "member_activity"
            case lastError = "last_error"
            case maxContinues = "max_continues"
            case routingModes = "routing_modes"
        }
    }

    let driverStatus: Driver?
    var context: RoomContext?

    private enum CodingKeys: String, CodingKey {
        case context
        case driverStatus = "driver_status"
    }
}

nonisolated private struct SentEvent: Decodable, Sendable {
    let event: RoomEvent
}

nonisolated private struct RoomLogPage: Decodable, Sendable {
    let events: [RoomEvent]
    let cursor: Int
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case events, cursor
        case hasMore = "has_more"
    }
}

nonisolated struct RoomParams: Encodable, Sendable {
    let roomID: String
    var sinceSeq: Int?
    var cancelID: String?
    var taskID: String?
    var memberID: String?
    var executionGeneration: Int?
    var discussionEventID: String?

    private enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case sinceSeq = "since_seq"
        case cancelID = "cancel_id"
        case taskID = "task_id"
        case memberID = "member_id"
        case executionGeneration = "execution_generation"
        case discussionEventID = "discussion_event_id"
    }
}

nonisolated struct SendParams: Encodable, Sendable {
    struct Payload: Encodable, Sendable {
        let text: String
        let threadID: String

        private enum CodingKeys: String, CodingKey {
            case text
            case threadID = "thread_id"
        }
    }

    let roomID: String
    let eventID: String
    let payload: Payload

    private enum CodingKeys: String, CodingKey {
        case payload
        case roomID = "room_id"
        case eventID = "event_id"
    }
}

nonisolated private struct ApproveParams: Encodable, Sendable {
    let roomID: String
    let memberID: String
    let taskID: String
    let executionGeneration: Int
    let choice: ApprovalChoice
    let requestID: String

    private enum CodingKeys: String, CodingKey {
        case choice
        case roomID = "room_id"
        case memberID = "member_id"
        case taskID = "task_id"
        case executionGeneration = "execution_generation"
        case requestID = "request_id"
    }
}

@Observable
final class GroupSession {
    let room: Room
    var failure: String?
    private(set) var events: [RoomEvent] = []
    private(set) var driver = RoomState.Driver()
    private(set) var context: RoomContext?
    private(set) var unsent: [Turn] = []
    private var answered: Set<String> = []
    private var retrying: Set<String> = []
    private var continuing: Set<String> = []
    private var cursor = 0
    private let gateway: Gateway

    init(room: Room, gateway: Gateway) {
        self.room = room
        self.gateway = gateway
    }

    convenience init(fixture room: Room, events: [RoomEvent], driver: RoomState.Driver, context: RoomContext? = nil) {
        self.init(room: room, gateway: Gateway(server: URL(filePath: "/"), urlSession: .shared) { throw CancellationError() })
        self.events = events
        self.driver = driver
        self.context = context
    }

    var isWorking: Bool { driver.working }

    var isAwaitingReply: Bool {
        isWorking || events.last.map { $0.kind == "message.user" && $0.routineTitle == nil } ?? false
    }

    var activity: String? {
        let running = (driver.memberActivity ?? []).filter { $0.status != "queued" }
        guard !running.isEmpty else { return nil }
        return running.map { row in
            let name = room.members.first { $0.memberID == row.memberID }.map { $0.displayName ?? $0.memberID } ?? row.memberID
            return [name, row.tool?.replacing("_", with: " ")].compactMap(\.self).joined(separator: " · ")
        }
        .joined(separator: ", ")
    }

    var hasMessages: Bool {
        !unsent.isEmpty || events.contains { $0.kind == "message.user" || $0.kind == "message.member" }
    }

    var transcript: Transcript {
        let retryable = Set(driver.pendingActions.filter { $0.kind == "retry" }.compactMap(\.taskID)).subtracting(retrying)
        let names = room.members.map { $0.displayName ?? $0.memberID }.formatted(.list(type: .and))
        let welcome = hasMessages ? [Turn(id: "welcome", notice: String(localized: "\(names) are in this group."), status: .complete, startedAt: room.createdAt, finishedAt: room.createdAt)] : []
        let resumable = resumablePauses
        let replies = events.indices.flatMap { index -> [Turn] in
            let event = events[index]
            let isSuperseded = event.kind == "turn.deferred" && events[(index + 1)...].contains { $0.payload.taskID == event.payload.taskID }
            return isSuperseded ? [] : turns(for: event, retryable: retryable, resumable: resumable)
        }
        let logged = Set(events.compactMap(\.payload.taskID))
        let stalled = retryable.subtracting(logged).sorted().map { id in
            let wake = driver.lastError.map { String(localized: "Members couldn't be woken: \($0)") } ?? String(localized: "Members couldn't be woken.")
            let failure = id.hasPrefix("prepare:") ? wake : String(localized: "A reply may not have finished.")
            return Turn(id: "retry-\(id)", status: .error, startedAt: events.last?.createdAt ?? room.createdAt, failure: failure, retryID: id)
        }
        let pending = unsent.filter { turn in !events.contains { $0.eventID == turn.id } }
        let started = (driver.memberActivity ?? []).filter { $0.status != "queued" }.compactMap(\.startedAt).min()
        let working = isWorking ? [Turn(id: "working", status: .streaming, startedAt: started ?? events.last?.createdAt ?? .now)] : []
        return Transcript(turns: welcome + (hasMessages ? replies : []) + stalled + pending + working)
    }

    private var resumablePauses: Set<String> {
        guard let limit = driver.maxContinues else { return [] }
        let lastStop = events.last { $0.kind == "room.stop_requested" }?.seq ?? 0
        return Set(events.indices.compactMap { index -> String? in
            let pause = events[index]
            guard pause.kind == "room.activity", pause.payload.status == "bounded", let discussion = pause.payload.discussionEventID else { return nil }
            let source = events.first { $0.eventID == discussion }?.seq ?? pause.seq
            let isMovedOn = events[(index + 1)...].contains { event in
                (["room.activity", "room.continued"].contains(event.kind) && event.payload.discussionEventID == discussion)
                    || (event.kind == "message.user" && event.payload.threadID == pause.payload.threadID)
            }
            let grants = events.count { $0.kind == "room.continued" && $0.payload.discussionEventID == discussion }
            return isMovedOn || lastStop > source || grants >= limit || continuing.contains(discussion) ? nil : pause.eventID
        })
    }

    var request: PendingRequest? {
        driver.pendingActions.lazy.compactMap { action -> PendingRequest? in
            guard action.kind == "approval", let id = action.requestID, !self.answered.contains(id), let approval = action.approval else { return nil }
            let member = self.room.members.first { $0.memberID == action.memberID }
            return .approval(ApprovalRequest(
                id: id,
                command: approval.command ?? "",
                description: approval.description ?? "",
                toolName: approval.toolName,
                choices: (approval.choices ?? []).compactMap(ApprovalChoice.init(rawValue:)),
                requester: member.map { $0.displayName ?? $0.memberID }
            ))
        }.first
    }

    func run() async {
        var tick = 0
        while !Task.isCancelled {
            if isAwaitingReply || tick % 5 == 0 { await refresh() }
            tick += 1
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func sendParams(_ text: String) -> SendParams {
        let id = UUID().uuidString
        return SendParams(roomID: room.id, eventID: id, payload: SendParams.Payload(text: text, threadID: id))
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let params = sendParams(text)
        let id = params.eventID
        unsent.append(Turn(id: id, prompt: Prompt(text: text, sentAt: .now), status: .complete, startedAt: .now, finishedAt: .now))
        Task {
            do {
                let sent = try await gateway.call("groups.send", params, as: SentEvent.self).event
                if let index = unsent.firstIndex(where: { $0.id == id }) { unsent[index].id = sent.eventID }
                driver.working = true
                await refresh()
            } catch {
                guard let index = unsent.firstIndex(where: { $0.id == id }) else { return }
                unsent[index].status = .error
                unsent[index].failure = String(localized: "Not sent: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        Task {
            do {
                _ = try await gateway.call("groups.stop", RoomParams(roomID: room.id, cancelID: "crew-stop-\(UUID().uuidString.lowercased())"), as: JSONValue.self)
                await refresh()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    func retryParams(for taskID: String) -> RoomParams {
        let action = driver.pendingActions.first { $0.kind == "retry" && $0.taskID == taskID }
        return RoomParams(roomID: room.id, taskID: taskID, memberID: action?.memberID, executionGeneration: action?.executionGeneration)
    }

    func retry(_ taskID: String) {
        let params = retryParams(for: taskID)
        retrying.insert(taskID)
        Task {
            defer { retrying.remove(taskID) }
            do {
                _ = try await gateway.call("groups.retry", params, as: JSONValue.self)
                await refresh()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    func continueDiscussion(_ discussionEventID: String) {
        guard continuing.insert(discussionEventID).inserted else { return }
        Task {
            defer { continuing.remove(discussionEventID) }
            do {
                _ = try await gateway.call("groups.continue", RoomParams(roomID: room.id, discussionEventID: discussionEventID), as: JSONValue.self)
                await refresh()
            } catch GatewayError.rpc {
                failure = String(localized: "This discussion can't be continued anymore.")
                await refresh()
            } catch {
                failure = error.localizedDescription
                await refresh()
            }
        }
    }

    func respond(to id: ApprovalRequest.ID, with choice: ApprovalChoice) {
        guard let action = driver.pendingActions.first(where: { $0.requestID == id }),
              let memberID = action.memberID, let taskID = action.taskID, let generation = action.executionGeneration
        else { return }
        answered.insert(id)
        Task {
            do {
                let params = ApproveParams(roomID: room.id, memberID: memberID, taskID: taskID, executionGeneration: generation, choice: choice, requestID: id)
                _ = try await gateway.call("groups.approve", params, as: JSONValue.self)
                await refresh()
            } catch {
                answered.remove(id)
                failure = error.localizedDescription
            }
        }
    }

    private func refresh() async {
        do {
            let state = try await gateway.call("groups.state", RoomParams(roomID: room.id), as: RoomState.self)
            while true {
                let page = try await gateway.call("groups.log", RoomParams(roomID: room.id, sinceSeq: cursor), as: RoomLogPage.self)
                let last = events.last?.seq ?? 0
                events += page.events.filter { $0.seq > last }
                unsent.removeAll { turn in page.events.contains { $0.eventID == turn.id } }
                cursor = max(cursor, page.cursor)
                guard page.hasMore else { break }
            }
            driver = state.driverStatus ?? RoomState.Driver()
            context = state.context
        } catch {}
    }

    private func turns(for event: RoomEvent, retryable: Set<String>, resumable: Set<String>) -> [Turn] {
        let date = event.createdAt
        if let title = event.routineTitle {
            let notice = Turn(id: "\(event.eventID)-routine", notice: String(localized: "Routine: \(title)"), status: .complete, startedAt: date, finishedAt: date)
            let text = event.payload.text ?? ""
            let output = event.actor.id?.hasPrefix("cron-notice:") == true
                ? Turn(id: event.eventID, status: .error, startedAt: date, finishedAt: date, failure: text)
                : Turn(id: event.eventID, reply: text, status: .complete, startedAt: date, finishedAt: date, speaker: event.routineOwner)
            return [notice, output]
        }
        if let notice = notice(for: event) {
            return [Turn(id: event.eventID, notice: notice, status: .complete, startedAt: date, finishedAt: date)]
        }
        return turn(for: event, retryable: retryable, resumable: resumable).map { [$0] } ?? []
    }

    private func notice(for event: RoomEvent) -> String? {
        let name = { (id: String) in self.room.members.first { $0.memberID == id }.map { $0.displayName ?? $0.memberID } }
        let payload = event.payload
        if event.kind == "room.context_set" {
            let previous = events.last { $0.kind == "room.context_set" && $0.seq < event.seq }.map(\.payload.context) ?? RoomContext()
            let lines = payload.context.changes(since: previous) { name($0) ?? $0 }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        if event.kind == "room.assignment", let leadID = payload.leadMemberID, let lead = name(leadID) {
            let chosen = payload.memberIDs ?? []
            let names = chosen.compactMap(name).formatted(.list(type: .and))
            let isTaking = payload.fallback == true || chosen == [leadID] || names.isEmpty
            return isTaking ? String(localized: "\(lead) is taking this") : String(localized: "\(lead) gave this to \(names)")
        }
        if event.kind == "room.routed" {
            if payload.fallback == true { return String(localized: "Couldn't choose who answers, so everyone will") }
            if payload.everyone == true { return String(localized: "Assigned to everyone") }
            let names = (payload.memberIDs ?? []).compactMap(name)
            return names.isEmpty ? nil : String(localized: "Assigned to \(names.formatted(.list(type: .and)))")
        }
        return nil
    }

    private func turn(for event: RoomEvent, retryable: Set<String>, resumable: Set<String>) -> Turn? {
        let date = event.createdAt
        let speaker = event.actor.profile ?? room.members.first { $0.memberID == event.payload.memberID }?.profile
        if event.kind == "message.user" {
            return Turn(id: event.eventID, prompt: Prompt(text: event.payload.text ?? "", sentAt: date), status: .complete, startedAt: date, finishedAt: date)
        }
        if event.kind == "message.member" {
            return Turn(id: event.eventID, reply: event.payload.text ?? "", status: .complete, startedAt: date, finishedAt: date, speaker: speaker)
        }
        if event.kind == "turn.failed" {
            return Turn(id: event.eventID, status: .error, startedAt: date, finishedAt: date, failure: event.payload.error, speaker: speaker)
        }
        if event.kind == "turn.deferred" {
            let retryID = event.payload.taskID.flatMap { retryable.contains($0) ? $0 : nil }
            return Turn(id: event.eventID, status: .error, startedAt: date, finishedAt: date, failure: String(localized: "This reply didn't finish."), speaker: speaker, retryID: retryID)
        }
        if event.kind == "turn.cancelled" {
            return Turn(id: event.eventID, status: .interrupted, startedAt: date, finishedAt: date, speaker: speaker)
        }
        if event.kind == "room.activity", event.payload.status == "bounded" {
            let count = events.count { $0.kind == "message.member" && $0.payload.discussionEventID == event.payload.discussionEventID && $0.seq < event.seq }
            let notice = String(AttributedString(localized: "Paused after ^[\(count) message](inflect: true)").characters)
            return Turn(id: event.eventID, notice: notice, status: .complete, startedAt: date, finishedAt: date, continueID: resumable.contains(event.eventID) ? event.payload.discussionEventID : nil)
        }
        if event.kind == "room.continued" {
            return Turn(id: event.eventID, notice: String(localized: "Continued"), status: .complete, startedAt: date, finishedAt: date)
        }
        if event.kind == "room.renamed", let name = event.payload.name {
            return Turn(id: event.eventID, notice: String(localized: "Renamed to \(name)"), status: .complete, startedAt: date, finishedAt: date)
        }
        return nil
    }
}
