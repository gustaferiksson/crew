import Foundation

nonisolated struct BotTurnFailure: LocalizedError {
    let errorDescription: String?
}

nonisolated struct SubmitStatus: Decodable, Sendable {
    let status: String?
}

nonisolated enum BotAnswer: Equatable, Sendable {
    case reply(String)
    case pending

    private struct Payload: Decodable {
        let text: String?
        let message: String?
        let status: String?
        let error: String?
    }

    static func wait(in session: RuntimeSessionID, for events: AsyncStream<GatewayEvent>, after submit: @escaping @Sendable () async throws -> SubmitStatus, until deadline: ContinuousClock.Instant) async throws -> BotAnswer {
        try await withThrowingTaskGroup(of: BotAnswer.self) { group in
            group.addTask {
                guard try await submit().status ?? "streaming" == "streaming" else { return .pending }
                for await event in events where event.sessionID == session && (event.type == "message.complete" || event.type == "error") {
                    let payload = try JSONDecoder().decode(Payload.self, from: JSONEncoder().encode(event.payload ?? .object([:])))
                    guard event.type == "message.complete", payload.status ?? "complete" == "complete" else {
                        throw BotTurnFailure(errorDescription: payload.error ?? payload.message)
                    }
                    return .reply(payload.text ?? "")
                }
                return .pending
            }
            group.addTask {
                try await Task.sleep(until: deadline)
                return .pending
            }
            let first = try await group.next() ?? .pending
            group.cancelAll()
            return first
        }
    }

    static func speech(from reply: String) -> String {
        markdownBlocks(from: a2uiFenced(reply))
            .filter { if case .code = $0.kind { false } else { true } }
            .map { String($0.content.characters).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
