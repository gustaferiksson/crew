import SwiftUI

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

struct MarkdownText: View {
    let source: String

    var body: some View {
        let blocks = markdownBlocks(from: source)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                MarkdownBlockView(block: block)
                    .padding(.top, block.id == 0 ? 0 : spacing(after: blocks[block.id - 1].kind, before: block.kind))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spacing(after previous: MarkdownBlock.Kind, before kind: MarkdownBlock.Kind) -> CGFloat {
        if case .listItem = previous, case .listItem = kind { return 4 }
        if case .heading = kind { return 16 }
        return 12
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block.kind {
        case .paragraph:
            Text(block.content)
        case .heading(let level):
            Text(block.content)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
        case .listItem(let marker, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 12, alignment: .trailing)
                Text(block.content)
            }
            .padding(.leading, CGFloat(depth - 1) * 20)
        case .code(let language):
            VStack(alignment: .leading, spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(String(block.content.characters).trimmingCharacters(in: .newlines))
                        .font(.callout.monospaced())
                        .fixedSize()
                }
                .scrollIndicators(.hidden)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        case .quote:
            Text(block.content)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: 4)
                }
        case .rule:
            Divider()
                .padding(.vertical, 4)
        }
    }
}
