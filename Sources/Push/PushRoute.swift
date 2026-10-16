import Foundation

nonisolated struct PushRoute: Equatable, Sendable {
    let profile: String
    let sessionID: String
    let installID: String?
    let kind: String?
    let requestID: String?
    let expiresAt: Date?

    init?(userInfo: [AnyHashable: Any]) {
        guard let crew = userInfo["crew"] as? [String: Any], let profile = crew["profile"] as? String, !profile.isEmpty else { return nil }
        self.profile = profile
        self.sessionID = crew["session_id"] as? String ?? ""
        self.installID = crew["install_id"] as? String
        self.kind = crew["kind"] as? String
        self.requestID = (crew["request_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.expiresAt = (crew["expires_at"] as? Double).map(Date.init(timeIntervalSince1970:))
    }

    func isStalePayment(at date: Date) -> Bool {
        kind == "payment" && (expiresAt ?? .distantPast) <= date
    }
}
