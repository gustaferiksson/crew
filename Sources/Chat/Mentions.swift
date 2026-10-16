import SwiftUI

nonisolated struct PathCompletion: Decodable, Sendable, Hashable {
    let text: String
    let display: String
    let meta: String?
}

extension Bot {
    var handle: String { name.lowercased() == "default" ? "hermes" : name }

    var mentionTags: Set<String> {
        let slug = (meta.title ?? "").lowercased().replacing(/[^a-z0-9_-]+/, with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return [handle.lowercased(), slug]
    }
}

func mentionedBots(in text: String, among bots: [Bot]) -> [Bot] {
    let tags = Set(text.matches(of: /(?:^|\s)@([A-Za-z0-9][A-Za-z0-9_-]*)/).map { $0.1.lowercased() })
    return bots.filter { !$0.mentionTags.isDisjoint(with: tags) }
}

nonisolated struct MentionSegment: Equatable {
    let text: String
    let bot: Bot?
}

func mentionSegments(in text: String, among bots: [Bot]) -> [MentionSegment] {
    var segments: [MentionSegment] = []
    var cursor = text.startIndex
    for match in text.matches(of: /(?:^|\s)@([A-Za-z0-9][A-Za-z0-9_-]*)/) {
        guard let bot = bots.first(where: { $0.mentionTags.contains(match.1.lowercased()) }) else { continue }
        let tag = text.index(before: match.1.startIndex)..<match.1.endIndex
        if cursor < tag.lowerBound { segments.append(MentionSegment(text: String(text[cursor..<tag.lowerBound]), bot: nil)) }
        segments.append(MentionSegment(text: String(text[tag]), bot: bot))
        cursor = tag.upperBound
    }
    if cursor < text.endIndex { segments.append(MentionSegment(text: String(text[cursor...]), bot: nil)) }
    return segments
}

struct MentionTag: TextAttribute {
    let index: Int
}

func mentionTagFrames(in layout: Text.Layout) -> [(index: Int, rect: CGRect)] {
    layout.flatMap { line in
        line.reduce(into: [(index: Int, rect: CGRect)]()) { frames, run in
            guard let index = run[MentionTag.self]?.index else { return }
            guard frames.last?.index == index else { return frames.append((index, run.typographicBounds.rect)) }
            frames[frames.count - 1].rect = frames[frames.count - 1].rect.union(run.typographicBounds.rect)
        }
    }
}

struct MentionTagRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for frame in mentionTagFrames(in: layout) {
            let capsule = Capsule().path(in: frame.rect)
            let sheen = Gradient(colors: [.white.opacity(0.32), .white.opacity(0.16)])
            context.fill(capsule, with: .linearGradient(sheen, startPoint: CGPoint(x: frame.rect.midX, y: frame.rect.minY), endPoint: CGPoint(x: frame.rect.midX, y: frame.rect.maxY)))
            context.stroke(Capsule().path(in: frame.rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.4)), lineWidth: 1)
        }
        for line in layout {
            context.draw(line)
        }
    }
}

@MainActor private var renderedMentionAvatars: [MentionAvatarKey: Image] = [:]

private struct MentionAvatarKey: Hashable {
    let name: String
    let meta: BotMeta
    let hasPhoto: Bool
    let scheme: ColorScheme
    let size: CGFloat
    let scale: CGFloat
}

@MainActor func mentionAvatar(for bot: Bot, photo: Image?, size: CGFloat, scheme: ColorScheme, scale: CGFloat) -> Image? {
    let key = MentionAvatarKey(name: bot.name, meta: bot.meta, hasPhoto: photo != nil, scheme: scheme, size: size, scale: scale)
    if let cached = renderedMentionAvatars[key] { return cached }
    let renderer = ImageRenderer(content: BotAvatar(bot: bot, status: .idle, photo: photo, size: size).environment(\.colorScheme, scheme))
    renderer.scale = scale
    guard let image = renderer.cgImage.map({ Image(decorative: $0, scale: scale) }) else { return nil }
    renderedMentionAvatars[key] = image
    return image
}

struct MentionCard: View {
    let bot: Bot
    let openBot: ((Bot.ID) -> Void)?

    @Environment(BotStore.self) private var roster
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 280

    private var status: BotStatus { roster.statuses[bot.id] ?? .idle }

    private var about: String? {
        [bot.meta.description, bot.description].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 16) {
            BotAvatar(bot: bot, status: status, photo: roster.photos[bot.id], size: 64)
            VStack(spacing: 4) {
                Text(bot.title)
                    .font(.title3.bold())
                    .lineLimit(2)
                Text(verbatim: "@\(bot.handle)")
                    .foregroundStyle(.secondary)
                if case .waiting(let kind) = status {
                    Text(kind == .approval ? "Needs approval" : "Waiting for you")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                } else if status == .working {
                    Text("Working")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else if status == .failed {
                    Text("Failed")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            if let about {
                Text(about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            if let openBot {
                Button("Open Chat", systemImage: "bubble.left.and.bubble.right") {
                    dismiss()
                    openBot(bot.id)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .foregroundStyle(Color.primary)
        #if os(macOS)
        .frame(width: 280)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }
}

func mentionNote(for bots: [Bot]) -> String {
    guard !bots.isEmpty else { return "" }
    let lines = bots.map { bot in
        let title = bot.meta.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "@\(bot.handle) = agent profile \"\(bot.name)\"" + (title.isEmpty ? "" : " (\"\(title)\")")
    }
    return "\n\n[@mentions resolved from the Bot Mode roster — the user is referring to: " + lines.joined(separator: "; ")
        + ". If they want one of these agents contacted, compose your own message and send it with your message_agent tool (agents on other connected machines are reachable too — the Desktop relays it); never forward the user\u{2019}s text verbatim. If this session has no message_agent tool, agent messaging is unavailable here — say so. Keep it brief: never narrate queueing or delivery, say at most one short line after message_agent, and relay the reply in one line when it arrives.]"
}

struct MentionPicker: View {
    let query: String
    let bots: [Bot]
    let completePath: (String) async -> [PathCompletion]
    let pick: (String) -> Void

    @Environment(BotStore.self) private var roster
    @State private var files: [PathCompletion] = []

    private var matches: [Bot] {
        let query = query.lowercased()
        return Array(bots.filter { query.isEmpty || $0.handle.lowercased().hasPrefix(query) || $0.title.lowercased().hasPrefix(query) }.prefix(8))
    }

    var body: some View {
        VStack {
            if !matches.isEmpty || !files.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(matches) { bot in
                            row(title: bot.title, detail: "@\(bot.handle)") {
                                BotAvatar(bot: bot, status: .idle, photo: roster.photos[bot.id], size: 24)
                            } action: {
                                pick("@\(bot.handle)")
                            }
                        }
                        ForEach(files, id: \.text) { file in
                            row(title: file.display, detail: file.meta ?? "") {
                                Image(systemName: file.text.hasPrefix("@folder:") ? "folder" : "doc")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                            } action: {
                                pick(file.text)
                            }
                        }
                    }
                    .padding(4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
                .glassEffect(in: .rect(cornerRadius: 20))
                .transition(.opacity)
            }
        }
        .task(id: query) {
            guard !query.isEmpty else { return files = [] }
            guard (try? await Task.sleep(for: .milliseconds(200))) != nil else { return }
            files = await completePath("@\(query)").filter { item in
                ["@file:", "@folder:"].contains { item.text.hasPrefix($0) && item.text.count > $0.count }
            }
        }
    }

    private func row(title: String, detail: String, @ViewBuilder icon: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon()
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
