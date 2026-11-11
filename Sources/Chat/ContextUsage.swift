import Foundation

nonisolated struct ContextUsage: Hashable, Sendable {
    let used: Int
    let window: Int

    var fraction: Double {
        min(1, Double(used) / Double(window))
    }

    var isHigh: Bool {
        fraction >= 0.4
    }

    var summary: String {
        let style = IntegerFormatStyle<Int>.number.notation(.compactName).precision(.fractionLength(0...1))
        return String(localized: "\(used.formatted(style)) of \(window.formatted(style)) tokens")
    }

    var percentUsed: String {
        String(localized: "\(fraction.formatted(.percent.precision(.fractionLength(0)))) used")
    }
}

nonisolated extension ContextUsage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case used = "context_used"
        case window = "context_max"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        used = try container.decode(Int.self, forKey: .used)
        window = try container.decode(Int.self, forKey: .window)
        guard window > 0 else { throw DecodingError.dataCorruptedError(forKey: .window, in: container, debugDescription: "Hermes reported no context window") }
    }
}

nonisolated struct ContextCategory: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let tokens: Int
}
