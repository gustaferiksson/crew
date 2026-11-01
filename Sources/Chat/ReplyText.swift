import SwiftUI

#if os(macOS)
struct ReplyText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(replySegments(from: source).enumerated()), id: \.offset) { offset, segment in
                switch segment {
                case .text(let text):
                    ReplySegmentText(text: text, source: source, offset: offset)
                case .card(let block):
                    SurfaceBlock(source: block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#else
struct ReplyText: View {
    let source: String

    @Environment(\.messageSelection) private var selection

    var body: some View {
        if let selection, selection.wrappedValue {
            let segments = buildReplySegments(from: source)
            let firstText = segments.firstIndex { if case .text = $0 { true } else { false } }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(segments.enumerated()), id: \.offset) { offset, segment in
                    switch segment {
                    case .text(let text):
                        SelectableText(text: text, startsSelected: offset == firstText, isSelecting: selection)
                    case .card(let block):
                        SurfaceBlock(source: block)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MarkdownText(source: source)
        }
    }
}
#endif
