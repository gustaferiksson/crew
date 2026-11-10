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

// NSCache is documented thread-safe but not marked Sendable.
nonisolated final class ParseCache<Value>: @unchecked Sendable {
    private final class Entry {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private let entries = NSCache<NSString, Entry>()

    init(costLimit: Int) {
        entries.totalCostLimit = costLimit
    }

    func value(for source: String, parse: (String) -> Value) -> Value {
        if let entry = entries.object(forKey: source as NSString) { return entry.value }
        let value = parse(source)
        entries.setObject(Entry(value), forKey: source as NSString, cost: source.utf8.count)
        return value
    }
}

nonisolated private let parsedMarkdown = ParseCache<[MarkdownBlock]>(costLimit: 4 * 1024 * 1024)

nonisolated func markdownBlocks(from source: String) -> [MarkdownBlock] {
    markdownSections(of: source)
        .flatMap { parsedMarkdown.value(for: $0, parse: parseMarkdownBlocks) }
        .enumerated()
        .map { MarkdownBlock(id: $0.offset, kind: $0.element.kind, content: $0.element.content) }
}

nonisolated func markdownSections(of source: String) -> [String] {
    var sections: [[Substring]] = [[]]
    var fence: Character?
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.drop { $0 == " " }
        if trimmed.hasPrefix("["), trimmed.contains("]:") { return [source] }
        let followsBlank = sections[sections.count - 1].last?.utf8.allSatisfy { $0 == 32 || $0 == 9 } == true
        if fence == nil, followsBlank, let first = line.first, !first.isWhitespace, !"-*+0123456789".contains(first) {
            sections.append([])
        }
        sections[sections.count - 1].append(line)
        if let open = fence {
            if trimmed.hasPrefix(String(repeating: open, count: 3)), trimmed.allSatisfy({ $0 == open || $0.isWhitespace }) { fence = nil }
        } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            fence = trimmed.first
        }
    }
    return sections.map { $0.joined(separator: "\n") }
}

nonisolated func parseMarkdownBlocks(from source: String) -> [MarkdownBlock] {
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
    let parse = { (text: Substring) in
        (try? AttributedString(markdown: String(text), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    guard source.contains(/^#{1,6}[ \t]/.anchorsMatchLineEndings()) else { return parse(source[...]) }
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
        guard let marker = line.prefixMatch(of: /#{1,6}[ \t]+/) else { return parse(line) }
        var heading = parse(line[marker.range.upperBound...])
        for run in heading.runs {
            heading[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
        }
        return heading
    }
    return lines.dropFirst().reduce(into: lines[0]) { text, line in
        text.append(AttributedString("\n"))
        text.append(line)
    }
}

nonisolated func a2uiFenced(_ text: String) -> String {
    guard text.contains("<a2ui-json>") else { return text }
    return text.replacing(/<a2ui-json>\s*(?:```[a-z]*\n)?(?<body>[\s\S]*?)\s*(?:```\s*)?<\/a2ui-json>/) { "```a2ui\n\($0.output.body)\n```" }
}
