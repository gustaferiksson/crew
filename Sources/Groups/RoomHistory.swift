import Foundation

nonisolated struct RoomHistory: Equatable, Sendable {
    let sessionID: String
    let messages: Int
}

nonisolated struct RoomSessionList: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        let id: String
        let resolvedID: String?
        let messageCount: Int?
        let liveMessageCount: Int?

        private enum CodingKeys: String, CodingKey {
            case id
            case resolvedID = "resolved_id"
            case messageCount = "message_count"
            case liveMessageCount = "live_message_count"
        }
    }

    let sessions: [Row]

    var history: RoomHistory? {
        sessions.first.map { RoomHistory(sessionID: $0.resolvedID ?? $0.id, messages: $0.liveMessageCount ?? $0.messageCount ?? 0) }
    }
}

nonisolated enum RoomCompression: Equatable, Sendable {
    case compressed(String)
    case pending
    case busy(String)
    case aborted(String)
}

nonisolated struct RoomCompressReply: Decodable, Sendable {
    struct Summary: Decodable, Sendable {
        let headline: String?
        let note: String?
        let aborted: Bool?
    }

    let status: String?
    let compressed: Bool?
    let lockHeld: Bool?
    let message: String?
    let summary: Summary?

    private enum CodingKeys: String, CodingKey {
        case status, compressed, message, summary
        case lockHeld = "lock_held"
    }

    var outcome: RoomCompression {
        if status == "pending" { return .pending }
        if lockHeld == true || compressed == false { return .busy(message ?? "") }
        if status == "aborted" || summary?.aborted == true { return .aborted(summary?.note ?? summary?.headline ?? message ?? "") }
        return .compressed(summary?.headline ?? message ?? "")
    }
}

func roomHistory(of profile: String, in roomID: String, via gateway: Gateway) async throws -> RoomHistory? {
    let params: [String: JSONValue] = ["profile": .string(profile), "title": .string("Group: \(roomID)"), "include_hidden": .bool(true)]
    return try await gateway.call("session.list", params, as: RoomSessionList.self).history
}

func compressRoomHistory(_ history: RoomHistory, of profile: String, via gateway: Gateway) async throws -> RoomCompression {
    let resumeParams: [String: JSONValue] = ["profile": .string(profile), "session_id": .string(history.sessionID), "omit_messages": .bool(true)]
    let resumed = try await gateway.call("session.resume", resumeParams, as: LiveSnapshot.self)
    do {
        return try await gateway.call("session.compress", ["session_id": resumed.sessionID.rawValue], as: RoomCompressReply.self, timeout: .seconds(660)).outcome
    } catch GatewayError.rpc(4009, let message) {
        return .busy(message)
    } catch GatewayError.timedOut {
        return .pending
    }
}

func roomHistoryLabel(_ history: RoomHistory??, isPeer: Bool, isOnline: Bool) -> String? {
    guard !isPeer else { return nil }
    guard isOnline, let history else { return String(localized: "Unavailable") }
    guard let history else { return String(localized: "No history") }
    return String(localized: "\(history.messages) in history")
}
