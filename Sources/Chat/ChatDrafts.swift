import Foundation
import Observation

@Observable
final class ChatDrafts {
    @Observable fileprivate final class Draft {
        var text: String

        init(_ text: String = "") {
            self.text = text
        }
    }

    static let shared = ChatDrafts()

    @ObservationIgnored private var drafts: [String: Draft]
    @ObservationIgnored private var trays: [String: AttachmentTray] = [:]
    private let fileURL: URL?

    var texts: [String: String] { drafts.mapValues(\.text).filter { !$0.value.isEmpty } }

    init(fileURL: URL? = URL.applicationSupportDirectory.appending(path: "drafts.json")) {
        self.fileURL = fileURL
        let stored = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        drafts = stored.mapValues { Draft($0) }
    }

    init(fixture texts: [String: String]) {
        fileURL = nil
        drafts = texts.mapValues { Draft($0) }
    }

    private func draft(for chat: String) -> Draft {
        if let draft = drafts[chat] { return draft }
        let draft = Draft()
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
        let draft = draft(for: chat)
        guard draft.text != text else { return }
        draft.text = text
        save()
    }

    func preview(for chat: String) -> String? {
        let text = text(for: chat).split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
        drafts.values.forEach { $0.text = "" }
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
