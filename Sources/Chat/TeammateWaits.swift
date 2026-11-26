import Foundation
import Observation

@Observable
final class TeammateWaits {
    private nonisolated struct Answer: Decodable, Sendable {
        let deliveries: [TeammateDelivery]
    }

    private(set) var rows: [TeammateDelivery] = []
    private(set) var isStale = false
    private(set) var isSupported = true

    func visible(excluding dismissed: DismissedDeliveries) -> [TeammateDelivery] {
        let shown = rows.filter { $0.state != .failed || !dismissed.contains($0.id) }
        return shown.filter { $0.state == .waitingOnYou } + shown.filter { $0.state != .waitingOnYou && $0.state != .failed } + shown.filter { $0.state == .failed }
    }

    func run(profile: String, dismissed: DismissedDeliveries, via gateway: Gateway) async {
        isSupported = true
        while isSupported, !Task.isCancelled {
            await refresh(dismissed: dismissed) { try await gateway.call("bot_delivery.list", ["profile": profile], as: Answer.self).deliveries }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    func refresh(dismissed: DismissedDeliveries, fetch: () async throws -> [TeammateDelivery]) async {
        do {
            rows = try await fetch()
            isStale = false
            dismissed.keep(listed: Set(rows.map(\.id)))
        } catch GatewayError.rpc(let code, let message) where code == -32601 || message.lowercased().contains("method not found") {
            rows = []
            isSupported = false
        } catch {
            if !Task.isCancelled { isStale = true }
        }
    }
}
