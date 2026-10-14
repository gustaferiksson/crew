import Foundation
import Observation

nonisolated struct RoomEvent: Decodable, Sendable, Equatable {
    struct Actor: Decodable, Sendable, Equatable {
        let profile: String?
    }

    struct Payload: Decodable, Sendable, Equatable {
        var text: String?
        var memberID: String?
        var error: String?
        var name: String?

        private enum CodingKeys: String, CodingKey {
            case text, error, name
            case memberID = "member_id"
        }
    }

    let seq: Int
    let eventID: String
    let kind: String
    let actor: Actor
    let payload: Payload
    let createdAt: Date

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

nonisolated private struct RoomState: Decodable, Sendable {
    struct Driver: Decodable, Sendable {
        let working: Bool
        let pendingActions: [RoomAction]

        private enum CodingKeys: String, CodingKey {
            case working
            case pendingActions = "pending_actions"
        }
    }

    let driverStatus: Driver?

    private enum CodingKeys: String, CodingKey {
        case driverStatus = "driver_status"
    }
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

nonisolated private struct RoomParams: Encodable, Sendable {
    let roomID: String
    var sinceSeq: Int?
    var cancelID: String?

    private enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case sinceSeq = "since_seq"
        case cancelID = "cancel_id"
    }
}

nonisolated private struct SendParams: Encodable, Sendable {
    struct Payload: Encodable, Sendable {
        let text: String
        let threadID = "main"

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
    private(set) var isWorking = false
    private(set) var actions: [RoomAction] = []
    private(set) var unsent: [Turn] = []
    private var answered: Set<String> = []
    private var cursor = 0
    private let gateway: Gateway

    init(room: Room, gateway: Gateway) {
        self.room = room
        self.gateway = gateway
    }

    convenience init(fixture room: Room, events: [RoomEvent], actions: [RoomAction], isWorking: Bool) {
        self.init(room: room, gateway: Gateway(server: URL(filePath: "/"), urlSession: .shared) { throw CancellationError() })
        self.events = events
        self.actions = actions
        self.isWorking = isWorking
    }

    var transcript: Transcript {
        let names = room.members.map { $0.displayName ?? $0.memberID }.formatted(.list(type: .and))
        let welcome = Turn(id: "welcome", notice: String(localized: "\(names) are in this group."), status: .complete, startedAt: room.createdAt, finishedAt: room.createdAt)
        let working = isWorking ? [Turn(id: "working", status: .streaming, startedAt: events.last?.createdAt ?? .now)] : []
        return Transcript(turns: [welcome] + events.compactMap(turn(for:)) + unsent + working)
    }

    var request: PendingRequest? {
        actions.lazy.compactMap { action -> PendingRequest? in
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
            if isWorking || tick % 5 == 0 { await refresh() }
            tick += 1
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = UUID().uuidString
        unsent.append(Turn(id: id, prompt: Prompt(text: text, sentAt: .now), status: .complete, startedAt: .now, finishedAt: .now))
        Task {
            do {
                let params = SendParams(roomID: room.id, eventID: id, payload: SendParams.Payload(text: text))
                _ = try await gateway.call("groups.send", params, as: JSONValue.self)
                isWorking = true
                await refresh()
                unsent.removeAll { $0.id == id }
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

    func respond(to id: ApprovalRequest.ID, with choice: ApprovalChoice) {
        guard let action = actions.first(where: { $0.requestID == id }),
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
                cursor = max(cursor, page.cursor)
                guard page.hasMore else { break }
            }
            isWorking = state.driverStatus?.working == true
            actions = state.driverStatus?.pendingActions ?? []
        } catch {}
    }

    private func turn(for event: RoomEvent) -> Turn? {
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
        if event.kind == "turn.cancelled" {
            return Turn(id: event.eventID, status: .interrupted, startedAt: date, finishedAt: date, speaker: speaker)
        }
        if event.kind == "room.renamed", let name = event.payload.name {
            return Turn(id: event.eventID, notice: String(localized: "Renamed to \(name)"), status: .complete, startedAt: date, finishedAt: date)
        }
        return nil
    }
}
