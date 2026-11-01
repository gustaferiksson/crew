import Foundation

nonisolated func speechText(from reply: String) -> String {
    markdownBlocks(from: a2uiFenced(reply)).compactMap { block -> String? in
        let text = String(block.content.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, block.kind != .rule else { return nil }
        if case .code = block.kind { return nil }
        let sentence = text.last.map { ".!?:;".contains($0) } == true ? text : text + "."
        guard case .listItem(let marker, _) = block.kind, marker != "•" else { return sentence }
        return "\(marker) \(sentence)"
    }
    .joined(separator: "\n")
}
