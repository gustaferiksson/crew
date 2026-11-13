import Foundation
import Observation

@Observable
final class CardTimers {
    static let shared = CardTimers()
    static let limit = 200

    struct Entry: Codable, Equatable {
        var state: String
        var changedAt = Date.now
    }

    private(set) var entries: [String: Entry]
    private let fileURL: URL?

    init(fileURL: URL? = URL.applicationSupportDirectory.appending(path: "timers.json")) {
        self.fileURL = fileURL
        entries = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    static func key(chat: String?, surface: String, timer: String) -> String {
        "timer.\(chat ?? "").\(surface).\(timer)"
    }

    func timer(_ key: String) -> CardTimer {
        CardTimer(entries[key]?.state)
    }

    func set(_ timer: CardTimer, for key: String) {
        entries[key] = timer.saved.map { Entry(state: $0) }
        for old in entries.sorted(by: { $0.value.changedAt < $1.value.changedAt }).dropLast(Self.limit) {
            entries[old.key] = nil
        }
        save()
    }

    func clear(_ chat: String) {
        entries = entries.filter { !$0.key.hasPrefix("timer.\(chat).") }
        save()
    }

    func reset() {
        entries = [:]
        save()
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
