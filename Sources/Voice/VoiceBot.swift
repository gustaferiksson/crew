import Foundation

nonisolated struct VoiceBot: Codable, Hashable, Sendable {
    let name: String
    let title: String
    let session: String?
    let lastActive: Date?
    let shape: String
    let color: String
    let expression: String?
    let hidden: Bool

    static let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.gustaf.crew")
    static let cacheURL = container?.appending(path: "Library/Caches/voice-bots.json")
    static let photoDirectory = container?.appending(path: "Library/Caches/avatars")

    static func cached() -> [VoiceBot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return cacheURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? decoder.decode([VoiceBot].self, from: $0) } ?? []
    }

    static func choose(_ name: String?, from bots: [VoiceBot]) -> VoiceBot? {
        let listed = bots.filter { !$0.hidden }
        return bots.first { $0.name == name } ?? listed.max { ($0.lastActive ?? .distantPast) < ($1.lastActive ?? .distantPast) }
    }
}
