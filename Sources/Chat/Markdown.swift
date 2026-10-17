import SwiftUI

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

    @Environment(\.surfaces) private var surfaces

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
        case .code(let language) where language == "a2ui" && surfaces != nil:
            SurfaceBlock(source: String(block.content.characters).trimmingCharacters(in: .newlines))
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
