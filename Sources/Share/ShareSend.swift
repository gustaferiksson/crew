import Foundation

nonisolated struct ShareFailure: LocalizedError {
    let errorDescription: String?
}

nonisolated func share(_ message: String, attachments: [Attachment], to bot: VoiceBot, on server: URL, with urlSession: URLSession) async throws {
    guard let gateway = await connectedGateway(to: server, with: urlSession) else {
        throw HermesError.unreachable(host: server.host() ?? server.absoluteString)
    }
    let deadline = Task {
        try await Task.sleep(for: .seconds(30))
        await gateway.disconnect()
    }
    do {
        let (_, snapshot) = try await openBotChat(bot.session.map(StoredSessionID.init(rawValue:)), profile: bot.name, via: gateway)
        guard snapshot.running != true || attachments.isEmpty else {
            throw ShareFailure(errorDescription: String(localized: "\(bot.title) is busy. Try again when it's done."))
        }
        try await submitPrompt(message, attachments: attachments, in: snapshot.sessionID, via: gateway)
    } catch {
        deadline.cancel()
        await gateway.disconnect()
        throw error
    }
    deadline.cancel()
    await gateway.disconnect()
}
