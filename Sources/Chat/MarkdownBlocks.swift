import Foundation

nonisolated struct MarkdownBlock: Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph
        case heading(level: Int)
        case listItem(marker: String, depth: Int)
        case code(language: String?)
        case quote
        case rule
    }

    let id: Int
    let kind: Kind
    let content: AttributedString
}

nonisolated func markdownBlocks(from source: String) -> [MarkdownBlock] {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
    guard let parsed = try? AttributedString(markdown: source, options: options) else {
        return [MarkdownBlock(id: 0, kind: .paragraph, content: AttributedString(source))]
    }
    return parsed.runs[\.presentationIntent].enumerated().map { offset, run in
        let (intent, range) = run
        let components = intent?.components ?? []
        let lists = components.filter { $0.kind == .orderedList || $0.kind == .unorderedList }
        let isOrdered = lists.first?.kind == .orderedList
        let kind: MarkdownBlock.Kind = components.lazy.compactMap { component -> MarkdownBlock.Kind? in
            switch component.kind {
            case .header(let level): .heading(level: level)
            case .codeBlock(let language): .code(language: language)
            case .listItem(let ordinal): .listItem(marker: isOrdered ? "\(ordinal)." : "•", depth: lists.count)
            case .blockQuote: .quote
            case .thematicBreak: .rule
            default: nil
            }
        }.first ?? .paragraph
        return MarkdownBlock(id: offset, kind: kind, content: AttributedString(parsed[range]))
    }
}

nonisolated func cardMarkdown(_ source: String) -> AttributedString {
    (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
}

nonisolated func a2uiFenced(_ text: String) -> String {
    text.replacing(/<a2ui-json>\s*(?:```[a-z]*\n)?(?<body>[\s\S]*?)\s*(?:```\s*)?<\/a2ui-json>/) { "```a2ui\n\($0.output.body)\n```" }
}
