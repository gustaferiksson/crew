import Foundation

nonisolated struct PinnedGlance: Codable, Equatable, Sendable {
    struct Progress: Codable, Equatable, Sendable {
        let done: Int
        let total: Int
    }

    let surface: String
    let title: String?
    let subtitle: String?
    let symbol: String
    let tone: String?
    let progress: Progress?
    var pinnedAt = Date.distantPast

    static let widgetKind = "dev.gustaf.crew.pinned-card"

    #if os(iOS)
    static let fileURL = VoiceBot.container?.appending(path: "Library/Application Support/pinned-cards.json")
    #else
    static let fileURL: URL? = nil
    #endif

    static func saved(at url: URL?) -> [String: PinnedGlance] {
        url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: PinnedGlance].self, from: $0) } ?? [:]
    }
}
