import SwiftUI

struct UserBubble: View {
    let text: String
    let mentionable: [Bot]
    let openBot: ((Bot.ID) -> Void)?

    @Environment(BotStore.self) private var roster
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 16
    @State private var card: Int?
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

    private var segments: [MentionSegment] { mentionSegments(in: text, among: mentionable) }

    private var content: Text {
        segments.enumerated().reduce(Text(verbatim: "")) { result, item in
            guard let bot = item.element.bot else { return Text("\(result)\(Text(verbatim: item.element.text))") }
            let avatar = mentionAvatar(for: bot, photo: roster.photos[bot.id], size: avatarSize, scheme: colorScheme, scale: displayScale)
                .map { Text("\(Text($0).baselineOffset(-avatarSize / 8))\u{202F}") } ?? Text(verbatim: "")
            let tag = Text("\u{202F}\(avatar)\(Text(verbatim: item.element.text).fontWeight(.semibold))\u{202F}")
            return Text("\(result)\(tag.customAttribute(MentionTag(index: item.offset)))")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .lineLimit(isFoldable && !isUnfolded ? 6 : nil)
                .textRenderer(MentionTagRenderer())
                .overlayPreferenceValue(Text.LayoutKey.self, tagButtons)
                .accessibilityActions {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        if let bot = segment.bot {
                            Button("Show \(bot.title)") { card = index }
                        }
                    }
                }
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
        .task {
            guard Snapshot.requested == .chatMentionCard else { return }
            card = segments.firstIndex { $0.bot != nil }
        }
    }

    private func tagButtons(for layouts: [Text.LayoutKey.AnchoredLayout]) -> some View {
        GeometryReader { proxy in
            let frames = layouts.flatMap { layout in
                mentionTagFrames(in: layout.layout).map { ($0.index, $0.rect.offsetBy(dx: proxy[layout.origin].x, dy: proxy[layout.origin].y)) }
            }
            let anchors = Dictionary(frames, uniquingKeysWith: { first, _ in first })
            ForEach(anchors.keys.sorted(), id: \.self) { index in
                if let bot = segments[index].bot, let rect = anchors[index] {
                    tagButton(index: index, bot: bot, rect: rect)
                }
            }
        }
    }

    private func tagButton(index: Int, bot: Bot, rect: CGRect) -> some View {
        Button {
            card = index
        } label: {
            Color.clear
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .hoverEffect(.highlight)
        #else
        .pointerStyle(.link)
        #endif
        .accessibilityHidden(true)
        .frame(width: rect.width, height: rect.height)
        .popover(isPresented: Binding(get: { card == index }, set: { if !$0 { card = nil } })) {
            MentionCard(bot: bot, openBot: openBot)
        }
        .position(x: rect.midX, y: rect.midY)
    }
}
