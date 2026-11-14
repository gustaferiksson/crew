import Foundation
import UniformTypeIdentifiers

nonisolated enum SharedItem: Equatable, Sendable {
    case text(String)
    case link(URL, title: String?)
    case file(Attachment)

    enum Representation: Equatable {
        case file(UTType)
        case url
        case text
    }

    static func representation(of types: [UTType]) -> Representation? {
        if let file = types.first(where: { $0.conforms(to: .data) && !$0.conforms(to: .url) && !$0.conforms(to: .text) }) {
            return .file(file)
        }
        if types.contains(where: { $0.conforms(to: .url) }) { return .url }
        if types.contains(where: { $0.conforms(to: .text) }) { return .text }
        return nil
    }

    static func message(note: String, items: [SharedItem]) -> String {
        let shared = items.compactMap { item -> String? in
            if case .text(let text) = item { return text }
            if case .link(let url, _) = item { return url.absoluteString }
            return nil
        }
        return ([note] + shared)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func attachments(in items: [SharedItem]) throws -> [Attachment] {
        let files = items.compactMap { item -> Attachment? in
            guard case .file(let attachment) = item else { return nil }
            return attachment
        }
        return try Attachment.validated(files, limits: .room)
    }
}
