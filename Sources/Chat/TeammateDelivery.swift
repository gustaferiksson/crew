import Foundation

nonisolated struct TeammateDelivery: Decodable, Sendable, Equatable, Identifiable {
    enum State: String, CaseIterable, Sendable {
        case waitingOnYou = "waiting_on_you"
        case working, claimed, queued, failed

        var urgency: Int { Self.allCases.firstIndex(of: self)! }
    }

    let id: String
    let target: String
    let targetHandle: String
    let state: State
    let since: Date
    let preview: String
    let waitingOn: String?
    let reason: String?
    let error: String?
    var queuedBehind = 0

    var isUnknownOutcome: Bool { state == .failed && reason == "unknown_outcome" }

    private enum CodingKeys: String, CodingKey {
        case target, state, since, preview, reason, error
        case id = "delivery_id"
        case targetHandle = "target_handle"
        case waitingOn = "waiting_on"
    }

    init(id: String, target: String, targetHandle: String? = nil, state: State, since: Date, preview: String = "", waitingOn: String? = nil, reason: String? = nil, error: String? = nil) {
        self.id = id
        self.target = target
        self.targetHandle = targetHandle ?? target
        self.state = state
        self.since = since
        self.preview = preview
        self.waitingOn = waitingOn
        self.reason = reason
        self.error = error
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        target = try container.decode(String.self, forKey: .target)
        targetHandle = try container.decodeIfPresent(String.self, forKey: .targetHandle) ?? target
        state = try State(rawValue: container.decode(String.self, forKey: .state)) ?? .queued
        since = try container.decode(Date.self, forKey: .since)
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
        waitingOn = try container.decodeIfPresent(String.self, forKey: .waitingOn)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    func teammate(in bots: [Bot], sender: String?) -> Bot? {
        bots.first { $0.name == target && $0.name != sender }
    }

    func status(for bot: String) -> String {
        switch state {
        case .queued: return queuedBehind == 0 ? String(localized: "Queued") : String(localized: "\(queuedBehind + 1) queued")
        case .claimed: return withQueued(String(localized: "Picked up"))
        case .working: return withQueued(String(localized: "Working on it"))
        case .waitingOnYou: return waitingOn == "approval" ? String(localized: "Needs your approval") : String(localized: "Needs your answer")
        case .failed:
            if isUnknownOutcome { return String(localized: "Outcome unknown. It may have acted, and Crew won't send it again.") }
            let failure = DeliveryFailure(reason: reason, detail: error, target: bot)
            if let sentence = failure.explanation(for: bot) { return sentence }
            if let error = error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty { return error }
            return String(localized: "Delivery to \(bot) failed.")
        }
    }

    private func withQueued(_ status: String) -> String {
        queuedBehind == 0 ? status : String(localized: "\(status), and \(queuedBehind) queued")
    }

    func age(at now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(since))
        if seconds < 60 { return String(localized: "now") }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
