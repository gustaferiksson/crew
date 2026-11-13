import Foundation
import Observation
import OrderedJSON

@Observable
final class CardState {
    static let shared = CardState()
    static let limit = 200

    struct Card: Codable, Equatable {
        var values: [String: OrderedJSON.JSONValue] = [:]
        var updates: Set<String> = []
        var changedAt = Date.now
    }

    private(set) var chats: [String: [String: Card]]
    private let fileURL: URL?

    init(fileURL: URL? = URL.applicationSupportDirectory.appending(path: "cards.json")) {
        self.fileURL = fileURL
        chats = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: [String: Card]].self, from: $0) } ?? [:]
    }

    func values(of card: String, in chat: String) -> [String: OrderedJSON.JSONValue] {
        chats[chat]?[card]?.values ?? [:]
    }

    func userChanged(_ changes: [String: OrderedJSON.JSONValue], on card: String, after updates: [String], in chat: String) {
        var entry = chats[chat]?[card] ?? Card()
        entry.values.merge(changes) { $1 }
        entry.updates.formUnion(updates)
        entry.changedAt = .now
        chats[chat, default: [:]][card] = entry

        let byAge = chats.flatMap { chat, cards in cards.map { (chat: chat, card: $0.key, changedAt: $0.value.changedAt) } }.sorted { $0.changedAt < $1.changedAt }
        for old in byAge.dropLast(Self.limit) {
            chats[old.chat]?[old.card] = nil
        }
        save()
    }

    func botUpdated(_ paths: [String], with update: String, on card: String, in chat: String) {
        guard var entry = chats[chat]?[card], !entry.updates.contains(update) else { return }
        entry.updates.insert(update)
        entry.values = entry.values.filter { saved in
            !paths.contains { $0 == "/" || saved.key == $0 || saved.key.hasPrefix($0 + "/") || $0.hasPrefix(saved.key + "/") }
        }
        chats[chat]?[card] = entry
        save()
    }

    func clear(_ chat: String) {
        guard chats[chat] != nil else { return }
        chats[chat] = nil
        save()
    }

    func reset() {
        chats = [:]
        save()
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(chats).write(to: fileURL, options: .atomic)
    }
}
