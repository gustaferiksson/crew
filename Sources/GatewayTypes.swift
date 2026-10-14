import Foundation
import Synchronization

nonisolated struct RuntimeSessionID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
}

nonisolated struct StoredSessionID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
}

nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

nonisolated enum GatewayStatus: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case retrying(after: Duration)
    case stopped(HermesError)
}

nonisolated enum GatewayError: Error, Equatable {
    case notConnected
    case disconnected
    case timedOut
    case silent
    case ticketRejected
    case unexpectedFrame
    case rpc(code: Int, message: String)
}

nonisolated struct GatewayEvent: Decodable, Sendable {
    let type: String
    let sessionID: RuntimeSessionID?
    let seq: Int?
    let payload: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case type, seq, payload
        case sessionID = "session_id"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID).flatMap { $0.isEmpty ? nil : RuntimeSessionID(rawValue: $0) }
        seq = try container.decodeIfPresent(Int.self, forKey: .seq)
        payload = try container.decodeIfPresent(JSONValue.self, forKey: .payload)
    }
}

nonisolated struct ServerRequest: Decodable, Sendable, Identifiable {
    let id: String
    let method: String
    let sessionID: RuntimeSessionID?
    let params: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, method, params
    }

    private enum ParamKeys: String, CodingKey {
        case sessionID = "session_id"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params) ?? .object([:])
        sessionID = try? container.nestedContainer(keyedBy: ParamKeys.self, forKey: .params).decodeIfPresent(RuntimeSessionID.self, forKey: .sessionID)
    }
}

nonisolated struct EventReplay: Decodable, Sendable {
    let events: [GatewayEvent]
    let latestSeq: Int
    let truncated: Bool
    let epoch: String
    let openRequests: [ServerRequest]

    private enum CodingKeys: String, CodingKey {
        case events, truncated, epoch
        case latestSeq = "latest_seq"
        case openRequests = "open_requests"
    }
}

nonisolated final class Broadcast<Element: Sendable>: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Element>.Continuation]>([:])

    func stream() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { $0[id] = nil }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    func yield(_ element: Element) {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield(element)
        }
    }
}

nonisolated extension GatewayError: LocalizedError {
    var errorDescription: String? {
        guard case .rpc(_, let message) = self else { return nil }
        return message
    }
}
