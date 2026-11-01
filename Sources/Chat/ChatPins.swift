import CryptoKit
import Foundation
import Observation

@Observable
final class ChatPins {
    static let shared = ChatPins()

    struct Card: Equatable {
        let surface: String
        let source: String
        let finishedAt: Date
    }

    struct Seen: Codable, Equatable {
        let fingerprint: String
        let finishedAt: Date
    }

    struct Pin: Codable, Equatable {
        var seen: Seen?
        var pinned: String?
    }

    private struct Stored: Codable {
        let since: Date
        let chats: [String: Pin]
    }

    private(set) var chats: [String: Pin]
    private var since: Date
    private let fileURL: URL?

    init(fileURL: URL? = URL.applicationSupportDirectory.appending(path: "pins.json")) {
        let stored = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        self.fileURL = fileURL
        since = stored?.since ?? .now
        chats = stored?.chats ?? [:]
        if stored == nil { save() }
    }

    init(fixture chats: [String: Pin]) {
        fileURL = nil
        since = .distantPast
        self.chats = chats
    }

    func pinned(in chat: String) -> String? {
        chats[chat]?.pinned
    }

    func arrived(_ card: Card, in chat: String) {
        let fingerprint = card.surface + ":" + SHA256.hash(data: Data(card.source.utf8)).map { String(format: "%02x", $0) }.joined()
        let seen = chats[chat]?.seen ?? Seen(fingerprint: "", finishedAt: since)
        guard card.finishedAt > seen.finishedAt, fingerprint != seen.fingerprint else { return }
        chats[chat] = Pin(seen: Seen(fingerprint: fingerprint, finishedAt: card.finishedAt), pinned: card.surface)
        save()
    }

    func pin(_ surface: String?, in chat: String) {
        guard chats[chat]?.pinned != surface else { return }
        chats[chat, default: Pin()].pinned = surface
        save()
    }

    func clear(_ chat: String) {
        guard chats[chat] != nil else { return }
        chats[chat] = nil
        save()
    }

    func reset() {
        chats = [:]
        since = .now
        save()
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Stored(since: since, chats: chats)).write(to: fileURL, options: .atomic)
    }
}
