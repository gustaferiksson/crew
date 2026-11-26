import Foundation
import Observation

@Observable
final class TeammateWaits {
    private nonisolated struct Answer: Decodable, Sendable {
        let deliveries: [TeammateDelivery]
    }

    private(set) var rows: [TeammateDelivery]
    private(set) var isStale: Bool
    private(set) var isSupported = true
    private let dismissed: DismissedDeliveries

    init(rows: [TeammateDelivery] = [], isStale: Bool = false, dismissed: DismissedDeliveries = .shared) {
        self.rows = rows
        self.isStale = isStale
        self.dismissed = dismissed
    }

    var visible: [TeammateDelivery] {
        let shown = rows.filter { $0.state != .failed || !dismissed.contains($0.id) }
        return shown.filter { $0.state == .waitingOnYou } + shown.filter { $0.state != .waitingOnYou && $0.state != .failed } + shown.filter { $0.state == .failed }
    }

    func dismiss(_ id: String) {
        dismissed.dismiss(id)
    }

    func run(profile: String, via gateway: Gateway) async {
        isSupported = true
        while isSupported, !Task.isCancelled {
            await refresh(profile: profile, via: gateway)
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func refresh(profile: String, via gateway: Gateway) async {
        do {
            let answer = try await gateway.call("bot_delivery.list", ["profile": profile], as: Answer.self)
            rows = answer.deliveries
            isStale = false
            dismissed.keep(listed: Set(answer.deliveries.map(\.id)))
        } catch GatewayError.rpc(let code, let message) where code == -32601 || message.lowercased().contains("method not found") {
            rows = []
            isSupported = false
        } catch {
            if !Task.isCancelled { isStale = true }
        }
    }
}
