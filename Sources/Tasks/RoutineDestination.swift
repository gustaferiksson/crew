import Foundation

nonisolated enum RoutineDestination: Hashable, Sendable {
    case history
    case room(String)
    case other(String)

    init(deliver: String?) {
        let raw = deliver?.trimmingCharacters(in: .whitespaces) ?? ""
        if raw.isEmpty || raw == "local" {
            self = .history
            return
        }
        guard raw.lowercased().hasPrefix("room:"), !raw.contains(",") else {
            self = .other(raw)
            return
        }
        let address = raw.dropFirst(5)
        self = .room(String(address.lastIndex(of: "@").map { address[..<$0] } ?? address))
    }

    var deliver: String {
        switch self {
        case .history: "local"
        case .room(let id): "room:\(id)@default"
        case .other(let raw): raw
        }
    }
}
