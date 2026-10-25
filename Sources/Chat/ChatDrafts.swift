import Foundation
import Observation

@Observable
final class ChatDrafts {
    static let shared = ChatDrafts()

    private(set) var texts: [String: String]
    @ObservationIgnored private var trays: [String: AttachmentTray] = [:]
    private let fileURL: URL?

    init(fileURL: URL? = URL.applicationSupportDirectory.appending(path: "drafts.json")) {
        self.fileURL = fileURL
        texts = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    init(fixture texts: [String: String]) {
        fileURL = nil
        self.texts = texts
    }

    func tray(for chat: String) -> AttachmentTray {
        if let tray = trays[chat] { return tray }
        let tray = AttachmentTray()
        trays[chat] = tray
        return tray
    }

    func update(_ chat: String, to text: String) {
        guard texts[chat, default: ""] != text else { return }
        texts[chat] = text.isEmpty ? nil : text
        save()
    }

    func preview(for chat: String) -> String? {
        let text = texts[chat, default: ""].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if !text.isEmpty { return text }
        let count = trays[chat]?.items.count ?? 0
        return count > 0 ? String(AttributedString(localized: "^[\(count) Attachment](inflect: true)").characters) : nil
    }

    func clear(_ chat: String) {
        trays[chat] = nil
        update(chat, to: "")
    }

    func reset() {
        trays = [:]
        texts = [:]
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        guard let fileURL else { return }
        let stored = texts.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
    }
}
