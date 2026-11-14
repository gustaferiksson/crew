import Foundation

nonisolated struct TodoItem: Hashable, Identifiable, Sendable {
    enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
        case cancelled
    }

    let id: String
    let content: String
    let status: Status
}

nonisolated extension TodoItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, content, status
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
        id = (try? container.decode(String.self, forKey: .id)) ?? (try? container.decode(Int.self, forKey: .id)).map(String.init) ?? content
        status = (try? container.decode(String.self, forKey: .status)).flatMap(Status.init(rawValue:)) ?? .pending
    }
}

nonisolated private struct ListParams: Encodable, Sendable {
    let profile: String
    let title = "Bot Chat"
    let includeHidden = true

    private enum CodingKeys: String, CodingKey {
        case profile, title
        case includeHidden = "include_hidden"
    }
}

nonisolated private struct CreateParams: Encodable, Sendable {
    let profile: String
    let title = "Bot Chat"
    let hidden = true
    let followProfileConfig = true

    private enum CodingKeys: String, CodingKey {
        case profile, title, hidden
        case followProfileConfig = "follow_profile_config"
    }
}

nonisolated struct ResumeParams: Encodable, Sendable {
    let sessionID: StoredSessionID
    let profile: String
    let omitMessages = true
    let inlineImages = false

    private enum CodingKeys: String, CodingKey {
        case profile
        case sessionID = "session_id"
        case omitMessages = "omit_messages"
        case inlineImages = "inline_images"
    }
}

nonisolated private struct AttachResult: Decodable, Sendable {
    let path: String
    let refText: String?

    private enum CodingKeys: String, CodingKey {
        case path
        case refText = "ref_text"
    }
}

nonisolated private struct StoredSessions: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        let id: StoredSessionID
    }

    let sessions: [Row]
}

nonisolated func openBotChat(_ known: StoredSessionID?, profile: String, via gateway: Gateway) async throws -> (stored: StoredSessionID?, snapshot: LiveSnapshot) {
    let stored = if let known { known } else {
        try await gateway.call("session.list", ListParams(profile: profile), as: StoredSessions.self).sessions.first?.id
    }
    if let stored {
        return (stored, try await gateway.call("session.resume", ResumeParams(sessionID: stored, profile: profile), as: LiveSnapshot.self))
    }
    let snapshot = try await gateway.call("session.create", CreateParams(profile: profile), as: LiveSnapshot.self)
    // session.create writes no row until the first prompt; a reaped runtime then resumes the key as an untitled, visible row.
    _ = try await gateway.call("session.title", ["session_id": snapshot.sessionID.rawValue, "title": "Bot Chat"], as: JSONValue.self)
    return (nil, snapshot)
}

nonisolated func attachRequest(for attachment: Attachment, in session: RuntimeSessionID) -> (method: String, params: [String: String])? {
    guard let data = attachment.data else { return nil }
    if attachment.kind == .image {
        return ("image.attach_bytes", ["session_id": session.rawValue, "content_base64": data.base64EncodedString(), "filename": attachment.name])
    }
    return ("file.attach", ["session_id": session.rawValue, "data_url": "data:\(attachment.mimeType);base64,\(data.base64EncodedString())", "name": attachment.name])
}

nonisolated func submitPrompt(_ text: String, attachments: [Attachment], in session: RuntimeSessionID, via gateway: Gateway) async throws {
    var staged: [String] = []
    do {
        var references: [String] = []
        for attachment in attachments {
            guard let (method, params) = attachRequest(for: attachment, in: session) else { continue }
            let result = try await gateway.call(method, params, as: AttachResult.self)
            if attachment.kind == .image {
                staged.append(result.path)
            } else {
                references.append(result.refText ?? "")
            }
        }
        let message = [references.joined(separator: "\n"), text].filter { !$0.isEmpty }.joined(separator: "\n\n")
        _ = try await gateway.call("prompt.submit", ["session_id": session.rawValue, "text": message.isEmpty ? imageOnlyPrompt : message], as: JSONValue.self)
    } catch {
        for path in staged {
            _ = try? await gateway.call("image.detach", ["session_id": session.rawValue, "path": path], as: JSONValue.self)
        }
        throw error
    }
}

nonisolated struct LiveSnapshot: Decodable, Sendable {
    struct Inflight: Decodable, Sendable {
        let user: String?
        let assistant: String?
        let displayKind: String?

        private enum CodingKeys: String, CodingKey {
            case user, assistant
            case displayKind = "display_kind"
        }
    }

    struct TodoState: Decodable, Sendable {
        let todos: [TodoItem]
        let revision: Int
    }

    struct Info: Decodable, Sendable {
        let usage: ContextUsage?

        private enum CodingKeys: String, CodingKey {
            case usage
        }

        init(from decoder: any Decoder) throws {
            usage = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(ContextUsage.self, forKey: .usage)
        }
    }

    let sessionID: RuntimeSessionID
    let storedSessionID: StoredSessionID?
    let messageCount: Int?
    let running: Bool?
    let turnStartedAt: Double?
    let inflight: Inflight?
    let todoState: TodoState?
    let openRequests: [ServerRequest]?
    let info: Info?

    private enum CodingKeys: String, CodingKey {
        case running, inflight, info
        case sessionID = "session_id"
        case storedSessionID = "stored_session_id"
        case messageCount = "message_count"
        case turnStartedAt = "turn_started_at"
        case todoState = "todo_state"
        case openRequests = "open_requests"
    }
}
