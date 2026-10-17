import Foundation
import Observation

@Observable
final class ChatSessions {
    private(set) var sessions: [Bot.ID: ChatSession]
    private var gateway: Gateway?
    private var runs: [Bot.ID: Task<Void, Never>] = [:]
    private var awaitedPayments: [Bot.ID: String] = [:]

    init(fixture sessions: [Bot.ID: ChatSession] = [:]) {
        self.sessions = sessions
    }

    func open(_ bot: Bot, on gateway: Gateway, urlSession: URLSession) {
        if self.gateway !== gateway {
            reset()
            self.gateway = gateway
        }
        guard sessions[bot.id] == nil else { return }
        let session = ChatSession(bot: bot, gateway: gateway, urlSession: urlSession)
        sessions[bot.id] = session
        if let requestID = awaitedPayments.removeValue(forKey: bot.id) { session.expectPayment(requestID) }
        runs[bot.id] = Task { await session.run() }
    }

    func expectPayment(_ requestID: String, for bot: Bot.ID) {
        guard let session = sessions[bot] else { return awaitedPayments[bot] = requestID }
        session.expectPayment(requestID)
    }

    func sync(with bots: [Bot]) {
        for bot in bots {
            sessions[bot.id]?.sync(to: bot.canonicalSession?.position)
        }
    }

    func status(of bot: Bot.ID, in store: BotStore) -> BotStatus {
        let status = store.statuses[bot] ?? .idle
        guard status == .idle || status == .unread, sessions[bot]?.transcript.turns.last?.status == .error else { return status }
        return .failed
    }

    func reset() {
        for run in runs.values { run.cancel() }
        runs = [:]
        sessions = [:]
        gateway = nil
    }
}
