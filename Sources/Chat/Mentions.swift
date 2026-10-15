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

func removingMention(of bot: Bot, from text: String) -> String {
    text.replacing(/(?:^|\s)@([A-Za-z0-9][A-Za-z0-9_-]*)/) { match in
        bot.mentionTags.contains(match.1.lowercased()) ? "" : match.0
    }
}

func mentionNote(for bots: [Bot]) -> String {
    guard !bots.isEmpty else { return "" }
    let lines = bots.map { bot in
        let title = bot.meta.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "@\(bot.handle) = agent profile \"\(bot.name)\"" + (title.isEmpty ? "" : " (\"\(title)\")")
    }
    return "\n\n[@mentions resolved from the Bot Mode roster — the user is referring to: " + lines.joined(separator: "; ")
        + ". If they want one of these agents contacted, compose your own message and send it with your message_agent tool (agents on other connected machines are reachable too — the Desktop relays it); never forward the user\u{2019}s text verbatim. If this session has no message_agent tool, agent messaging is unavailable here — say so.]"
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

struct MentionChips: View {
    let bots: [Bot]
    let tap: (Bot) -> Void

    @Environment(BotStore.self) private var roster

    var body: some View {
        HStack(spacing: 8) {
            ForEach(bots) { bot in
                Button {
                    tap(bot)
                } label: {
                    HStack(spacing: 4) {
                        BotAvatar(bot: bot, status: .idle, photo: roster.photos[bot.id], size: 20)
                        Text(verbatim: "@\(bot.handle)")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.accentColor.opacity(0.12)).interactive(), in: .capsule)
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
            }
        }
    }
}
