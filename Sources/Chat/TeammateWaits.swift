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
        Self.grouped(rows.filter { $0.state != .failed || !dismissed.contains($0.id) })
    }

    static func grouped(_ shown: [TeammateDelivery]) -> [TeammateDelivery] {
        let ordered = shown.filter { $0.state == .waitingOnYou } + shown.filter { $0.state != .waitingOnYou && $0.state != .failed } + shown.filter { $0.state == .failed }
        let live = ordered.filter { $0.state != .failed }
        let leads = Dictionary(grouping: live, by: \.target).mapValues { $0.min { $0.state.urgency < $1.state.urgency }!.id }
        let folded = Dictionary(grouping: live.filter { $0.state == .queued && $0.id != leads[$0.target] }, by: \.target).mapValues(\.count)
        return ordered.compactMap { row in
            if row.state == .failed { return row }
            guard row.id == leads[row.target] else { return row.state == .queued ? nil : row }
            var lead = row
            lead.queuedBehind = folded[row.target] ?? 0
            return lead
        }
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
