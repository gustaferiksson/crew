import Foundation

nonisolated struct VoiceFailure: LocalizedError {
    let errorDescription: String?
}

nonisolated private struct ReplyPayload: Decodable {
    let text: String?
    let message: String?
    let status: String?
    let error: String?
}

nonisolated private struct SpokenAudio: Decodable {
    let dataUrl: String
}

nonisolated enum VoiceTurn {
    static let quietLevel = 0.35
    static let quietSpan = 12

    static func utterance(text: String, settled: String, heard: Int, levels: [Double]) -> String? {
        guard text == settled, settled.count > heard, levels.count >= quietSpan, levels.suffix(quietSpan).allSatisfy({ $0 < quietLevel }) else { return nil }
        let spoken = settled.dropFirst(heard).trimmingCharacters(in: .whitespacesAndNewlines)
        return spoken.isEmpty ? nil : spoken
    }

    static func reply(to text: String, in session: RuntimeSessionID, via gateway: Gateway) async throws -> String {
        let events = gateway.events()
        _ = try await gateway.call("prompt.submit", ["session_id": session.rawValue, "text": text], as: JSONValue.self)
        for await event in events where event.sessionID == session && ["message.complete", "error"].contains(event.type) {
            let payload = try JSONDecoder().decode(ReplyPayload.self, from: JSONEncoder().encode(event.payload ?? .object([:])))
            guard event.type == "message.complete", (payload.status ?? "complete") == "complete" else {
                throw VoiceFailure(errorDescription: payload.error ?? payload.message ?? String(localized: "The bot couldn't answer."))
            }
            return payload.text ?? ""
        }
        throw CancellationError()
    }

    static func audio(speaking text: String, profile: String, on server: URL, with urlSession: URLSession) async throws -> Data {
        var request = hermesRequest("api/audio/speak", on: server, json: ["text": text])
        request.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile)])
        request.timeoutInterval = 60
        let spoken = try await fetch(request, with: urlSession, as: SpokenAudio.self)
        guard let base64 = spoken.dataUrl.split(separator: ",", maxSplits: 1).last, let data = Data(base64Encoded: String(base64)) else {
            throw HermesError.invalidResponse
        }
        return data
    }
}
