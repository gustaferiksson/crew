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

nonisolated struct MentionExchange: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case sending
        case awaiting
        case replied(String, at: Date)
        case delivered
        case failed(String?)
        case relayed
    }

    let message: String
    let outcome: Outcome
}

nonisolated private struct MessageAgentCall {
    let target: String
    let message: String
    let call: ToolCall
    let result: [String: Any]

    var process: String? { call.status == .success ? result["process_id"] as? String : nil }

    static func all(in turn: Turn) -> [MessageAgentCall] {
        turn.work.compactMap { item in
            guard case .tool(let call) = item.kind, call.name == "message_agent" else { return nil }
            let arguments = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
            let target = (arguments["target"] as? String ?? call.subject).trimmingCharacters(in: .whitespaces).trimmingPrefix("@").prefix { $0 != "@" }.lowercased()
            let result = call.result.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] } ?? [:]
            return MessageAgentCall(target: target == "hermes" ? "default" : target, message: arguments["message"] as? String ?? "", call: call, result: result)
        }
    }
}

nonisolated func mentionExchange(with bot: Bot.ID, from turn: Turn.ID, in transcript: Transcript) -> MentionExchange? {
    let handle = bot.lowercased()
    guard let start = transcript.turns.firstIndex(where: { $0.id == turn }),
          let match = MessageAgentCall.all(in: transcript.turns[start]).last(where: { $0.target == handle })
    else { return nil }
    if match.call.status == .running { return MentionExchange(message: match.message, outcome: .sending) }
    let reason = (match.result["error"] ?? match.result["detail"]) as? String ?? match.call.outcome
    guard match.call.status == .success else { return MentionExchange(message: match.message, outcome: .failed(reason)) }
    guard let process = match.process else {
        let isQueued = ["queued", "sent", "delivered"].contains(match.result["status"] as? String ?? "")
        return MentionExchange(message: match.message, outcome: isQueued ? .relayed : .failed(reason))
    }
    var awaited: [String] = []
    for turn in transcript.turns {
        if turn.prompt != nil { awaited += MessageAgentCall.all(in: turn).filter { $0.target == handle }.compactMap(\.process) }
        guard turn.agentMessage?.handle == handle, let message = turn.agentMessage, !awaited.isEmpty else { continue }
        guard awaited.removeFirst() == process else { continue }
        return MentionExchange(message: match.message, outcome: .replied(message.body, at: turn.startedAt))
    }
    let isDelivered = transcript.turns[start...].contains { $0.delivery == process }
    return MentionExchange(message: match.message, outcome: isDelivered ? .delivered : .awaiting)
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
