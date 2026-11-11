import Foundation
import Observation

@Observable
final class ChatDrafts {
    static let shared = ChatDrafts()

    @ObservationIgnored private var drafts: [String: Draft] = [:]
    @ObservationIgnored private var trays: [String: AttachmentTray] = [:]
    private let fileURL: URL?

    var texts: [String: String] { drafts.mapValues(\.text).filter { !$0.value.isEmpty } }

    init(fileURL: URL? = URL.applicationSupportDirectory.appending(path: "drafts.json")) {
        self.fileURL = fileURL
        let stored = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        drafts = stored.mapValues { Draft($0, save: { [weak self] in self?.save() }) }
    }

    init(fixture texts: [String: String]) {
        fileURL = nil
        drafts = texts.mapValues { Draft($0) }
    }

    func draft(for chat: String) -> Draft {
        if let draft = drafts[chat] { return draft }
        let draft = Draft(save: { [weak self] in self?.save() })
        drafts[chat] = draft
        return draft
    }

    func tray(for chat: String) -> AttachmentTray {
        if let tray = trays[chat] { return tray }
        let tray = AttachmentTray()
        trays[chat] = tray
        return tray
    }

    func text(for chat: String) -> String {
        draft(for: chat).text
    }

    func update(_ chat: String, to text: String) {
        draft(for: chat).text = text
    }

    func preview(for chat: String) -> String? {
        let text = text(for: chat).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if !text.isEmpty { return text }
        let count = trays[chat]?.items.count ?? 0
        return count > 0 ? String(AttributedString(localized: "^[\(count) Attachment](inflect: true)").characters) : nil
    }

    func clear(_ chat: String) {
        trays[chat] = nil
        drafts[chat]?.reply = nil
        update(chat, to: "")
    }

    func reset() {
        trays = [:]
        drafts.values.forEach {
            $0.text = ""
            $0.reply = nil
        }
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
