import SwiftUI

struct UserBubble: View {
    let text: String
    let mentionable: [Bot]
    let turnID: Turn.ID
    var pending: Turn.Pending?
    var unqueue: (() -> Void)?

    @Environment(BotStore.self) private var roster
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 16
    @State private var card: MentionPick?

    private let shape = UnevenRoundedRectangle(
        cornerRadii: RectangleCornerRadii(topLeading: 19, bottomLeading: 19, bottomTrailing: 2, topTrailing: 19),
        style: .circular
    )

    private var fill: Color {
        colorSchemeContrast == .increased ? Color(red: 0, green: 0x40 / 255, blue: 0xDD / 255) : .blue
    }

    private func content(_ segments: [MentionSegment]) -> Text {
        segments.enumerated().reduce(Text(verbatim: "")) { result, item in
            guard let bot = item.element.bot else { return Text("\(result)\(Text(verbatim: item.element.text))") }
            let avatar = mentionAvatar(for: bot, photo: roster.photos[bot.id], size: avatarSize, scheme: colorScheme, scale: displayScale)
                .map { Text("\(Text($0).baselineOffset(-avatarSize / 8))\u{202F}") } ?? Text(verbatim: "")
            var title = AttributedString(bot.title.replacing(" ", with: "\u{00A0}"))
            title.link = URL(string: "crew-mention:\(item.offset)")
            let tag = Text("\u{00A0}\(avatar)\(Text(title).fontWeight(.semibold))\u{00A0}")
            return Text("\(result)@\u{202F}\(tag.customAttribute(MentionTag(index: item.offset)))")
        }
    }

    var body: some View {
        let segments = mentionSegments(in: text, among: mentionable)
        let content = content(segments)
        let picked = card.flatMap { pick in segments.indices.contains(pick.index) && segments[pick.index].bot?.id == pick.bot ? segments[pick.index].bot : nil }
        let bubbleText = content
            .textRenderer(MentionTagRenderer())
            .overlayPreferenceValue(Text.LayoutKey.self) { tagButtons(for: $0, in: segments, picked: picked) }
            .tint(.white)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "crew-mention", let index = Int(url.absoluteString.replacing("crew-mention:", with: "")),
                      let bot = segments.indices.contains(index) ? segments[index].bot : nil
                else { return .systemAction }
                card = MentionPick(index: index, bot: bot.id)
                return .handled
            })
            .foregroundStyle(pending == nil ? Color.white : fill)
        SelectingBubbleText(segments: segments, color: pending == nil ? .white : fill, isFilled: pending == nil) { bubbleText }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if pending == nil {
                    shape.fill(fill)
                } else {
                    shape.strokeBorder(fill, lineWidth: 1)
                }
            }
            .modifier(MessageMenu(text: text, shape: shape, remove: pending == .queued ? unqueue : nil))
        .containerRelativeFrame(.horizontal, alignment: .trailing) { length, _ in min(length * 0.75, 560) }
        .frame(maxWidth: .infinity, alignment: .trailing)
        #if os(iOS)
        .sheet(isPresented: Binding(get: { picked != nil }, set: { if !$0 { card = nil } })) {
            if let picked {
                MentionSheet(bot: picked, turnID: turnID)
            }
        }
        #endif
        .task {
            guard [.chatMentionPeek, .chatMentionChat].contains(Snapshot.requested), let index = segments.firstIndex(where: { $0.bot != nil }), let bot = segments[index].bot else { return }
            card = MentionPick(index: index, bot: bot.id)
        }
    }

    private func tagButtons(for layouts: [Text.LayoutKey.AnchoredLayout], in segments: [MentionSegment], picked: Bot?) -> some View {
        GeometryReader { proxy in
            let frames = layouts.flatMap { layout in
                mentionTagFrames(in: layout.layout).map { ($0.index, $0.rect.offsetBy(dx: proxy[layout.origin].x, dy: proxy[layout.origin].y)) }
            }
            let anchors = Dictionary(frames, uniquingKeysWith: { first, _ in first })
            ForEach(anchors.keys.sorted(), id: \.self) { index in
                if let bot = segments[index].bot, let rect = anchors[index] {
                    tagButton(index: index, bot: bot, rect: rect, picked: picked)
                }
            }
        }
    }

    private func tagButton(index: Int, bot: Bot, rect: CGRect, picked: Bot?) -> some View {
        Button {
            card = MentionPick(index: index, bot: bot.id)
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
        #if os(macOS)
        .popover(isPresented: Binding(get: { card?.index == index && picked != nil }, set: { if !$0 { card = nil } })) {
            MentionPeek(bot: bot, turnID: turnID) {
                card = nil
                openWindow(value: bot.id)
            }
            .frame(width: 320)
        }
        #endif
        .position(x: rect.midX, y: rect.midY)
    }
}

private struct SelectingBubbleText<Content: View>: View {
    let segments: [MentionSegment]
    let color: Color
    let isFilled: Bool
    @ViewBuilder let content: Content

    @Environment(\.messageSelection) private var selection

    var body: some View {
        #if os(iOS)
        if let selection, selection.wrappedValue {
            SelectableText(text: selectableText, tint: isFilled ? .white : nil, isSelecting: selection)
        } else {
            content
        }
        #else
        // Selectable text on macOS keeps its old colour when a waiting steer fills in place, leaving blue on blue (#87).
        content
            .textSelection(.enabled)
            .id(isFilled)
        #endif
    }

    #if os(iOS)
    private var selectableText: NSAttributedString {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let semibold = UIFont.systemFont(ofSize: body.pointSize, weight: .semibold)
        let text = NSMutableAttributedString()
        for segment in segments {
            guard let bot = segment.bot else {
                text.append(NSAttributedString(string: segment.text, attributes: [.font: body, .foregroundColor: UIColor(color)]))
                continue
            }
            let tag = NSMutableAttributedString(string: "@\u{202F}\u{00A0}", attributes: [.font: body, .foregroundColor: UIColor(color)])
            tag.append(NSAttributedString(string: bot.title.replacing(" ", with: "\u{00A0}") + "\u{00A0}", attributes: [.font: semibold, .foregroundColor: UIColor(color)]))
            tag.addAttribute(.replyPlainText, value: "@ \(bot.title) ", range: NSRange(location: 0, length: tag.length))
            text.append(tag)
        }
        return text
    }
    #endif
}

private struct MentionPick: Equatable {
    let index: Int
    let bot: Bot.ID
}
