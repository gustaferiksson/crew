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
typealias ReplyText = MarkdownText
#endif
