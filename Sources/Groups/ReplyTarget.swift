import Foundation

nonisolated struct ReplyTarget: Equatable, Sendable {
    let messageID: String
    let thread: String
    let name: String
    let handle: String?
    let quote: String

    func addressing(_ draft: String, replacing previous: ReplyTarget?) -> String {
        let stale = previous?.handle.map { "@\($0) " }
        let text = stale.map { draft.hasPrefix($0) ? String(draft.dropFirst($0.count)) : draft } ?? draft
        guard let handle else { return text }
        return text.trimmingPrefix(while: \.isWhitespace).hasPrefix("@\(handle)") ? text : "@\(handle) \(text)"
    }
}
