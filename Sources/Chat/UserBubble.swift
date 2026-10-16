import SwiftUI

struct UserBubble: View {
    let text: String
    let mentionable: [Bot]
    let openBot: (Bot.ID) -> Void

    @State private var isUnfolded = false
    @State private var fullHeight: CGFloat = 0
    @State private var foldThreshold: CGFloat = 0

    private let shape = UnevenRoundedRectangle(
        cornerRadii: RectangleCornerRadii(topLeading: 19, bottomLeading: 19, bottomTrailing: 2, topTrailing: 19),
        style: .circular
    )

    private static let fill = LinearGradient(
        colors: [
            Color(.displayP3, red: 0x57 / 255, green: 0xA4 / 255, blue: 0xF6 / 255),
            Color(.displayP3, red: 0x52 / 255, green: 0x9F / 255, blue: 0xF5 / 255),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    private var isFoldable: Bool { fullHeight > foldThreshold + 1 }

    private var content: Text {
        mentionSegments(in: text, among: mentionable).reduce(Text(verbatim: "")) { result, segment in
            guard let bot = segment.bot else { return Text("\(result)\(Text(verbatim: segment.text))") }
            var tag = AttributedString(segment.text)
            tag.link = URL(string: "crew-bot:\(bot.id)")
            return Text("\(result)\(Text(tag).fontWeight(.semibold).customAttribute(MentionTag()))")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .textRenderer(MentionTagRenderer(fill: .white.opacity(0.24)))
                .tint(.white)
                .environment(\.openURL, OpenURLAction { url in
                    guard let bot = mentionable.first(where: { url.absoluteString == "crew-bot:\($0.id)" }) else { return .systemAction }
                    openBot(bot.id)
                    return .handled
                })
                .lineLimit(isFoldable && !isUnfolded ? 6 : nil)
                .background {
                    content
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                }
                .background {
                    content
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { foldThreshold = $0 }
                }
            if isFoldable {
                Button(isUnfolded ? "Show less" : "Show more") {
                    withAnimation(.snappy) { isUnfolded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .foregroundStyle(.white)
        #if os(macOS)
        .textSelection(.enabled)
        #endif
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Self.fill, in: shape)
        .modifier(MessageMenu(text: text, shape: shape))
        .containerRelativeFrame(.horizontal, alignment: .trailing) { length, _ in min(length * 0.75, 560) }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
