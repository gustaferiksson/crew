import SwiftUI

struct MentionPeek: View {
    let bot: Bot
    let turnID: Turn.ID
    let showChat: () -> Void

    @Environment(BotStore.self) private var roster
    @Environment(ChatSessions.self) private var chats
    @Environment(\.chatSession) private var session

    private var exchange: MentionExchange? {
        session.flatMap { mentionExchange(with: bot.id, from: turnID, in: $0.transcript) }
    }

    private var status: BotStatus { chats.status(of: bot.id, in: roster) }

    private var about: String? {
        [bot.meta.description, bot.description].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BotAvatar(bot: bot, status: status, photo: roster.photos[bot.id], size: 44)
                VStack(alignment: .leading) {
                    Text(bot.title)
                        .font(.headline)
                        .lineLimit(2)
                    statusText
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: showChat) {
                VStack(alignment: .leading, spacing: 12) {
                    if let exchange {
                        if !exchange.message.isEmpty {
                            section("Message to \(bot.title)", text: exchange.message)
                        }
                        outcome(exchange.outcome)
                    } else {
                        section("Recent", date: bot.canonicalSession?.lastActive, text: bot.canonicalSession?.preview ?? String(localized: "No messages yet"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(16)
                }
                .background(.fill.quaternary, in: .rect(cornerRadius: 20))
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows \(bot.title)'s chat")
            if let about {
                Text(about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(20)
        .foregroundStyle(Color.primary)
        .accessibilityAction(named: "Show Chat", showChat)
    }

    private var statusText: Text {
        let handle = Text(verbatim: "@\(bot.handle)")
        if case .waiting(let kind) = status {
            return Text("\(handle) · \(Text(kind == .approval ? "Needs approval" : "Waiting for you").foregroundStyle(.orange))")
        }
        if status == .working {
            return Text("\(handle) · \(Text(chats.sessions[bot.id]?.statusLine ?? String(localized: "Working")).foregroundStyle(.green))")
        }
        if status == .failed {
            return Text("\(handle) · \(Text("Failed").foregroundStyle(.red))")
        }
        guard let date = bot.canonicalSession?.lastActive else { return handle }
        return Text("\(handle) · Active \(date, format: .relative(presentation: .named))")
    }

    @ViewBuilder
    private func outcome(_ outcome: MentionExchange.Outcome) -> some View {
        if case .replied(let reply, let date) = outcome {
            section("\(bot.title)'s reply", date: date, text: reply)
        } else if outcome == .awaiting, status == .working {
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .phaseAnimator([1, 0.4]) { dot, opacity in
                        dot.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 1)
                    }
                Text("Waiting for \(bot.title)")
            }
            .foregroundStyle(.secondary)
        } else if outcome == .awaiting {
            Text("No reply yet")
                .foregroundStyle(.secondary)
        } else if outcome == .sending {
            Text("Sending…")
                .foregroundStyle(.secondary)
        } else if outcome == .delivered {
            Text("Delivered. The answer is in \(bot.title)'s chat.")
                .foregroundStyle(.secondary)
        } else if outcome == .relayed {
            Text("Sent through Hermes Desktop. The reply shows there.")
                .foregroundStyle(.secondary)
        } else if case .failed(let reason) = outcome {
            VStack(alignment: .leading, spacing: 4) {
                Text("Not delivered")
                    .foregroundStyle(.red)
                if let reason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func section(_ title: LocalizedStringKey, date: Date? = nil, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                if let date {
                    Text(verbatim: "·")
                    Text(date, format: .relative(presentation: .named))
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.trailing, 16)
            Text(text)
                .lineLimit(4)
        }
    }
}

#if os(iOS)
struct MentionSheet: View {
    let bot: Bot
    let turnID: Turn.ID

    @State private var detent: PresentationDetent = Snapshot.requested == .chatMentionChat ? .large : .medium
    @State private var models = ModelSwitcher()
    @State private var showsBot = false

    var body: some View {
        Group {
            if detent == .large {
                NavigationStack {
                    ChatScreen(bot: bot, models: models, showsBot: $showsBot) { _ in }
                }
            } else {
                ScrollView {
                    MentionPeek(bot: bot, turnID: turnID) {
                        withAnimation(.smooth) { detent = .large }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}
#else
struct BotChatWindow: View {
    let id: Bot.ID?

    @Environment(BotStore.self) private var bots
    @State private var models = ModelSwitcher()
    @State private var showsBot = false

    var body: some View {
        if let bot = bots.bots.first(where: { $0.id == id }) {
            NavigationStack {
                ChatScreen(bot: bot, models: models, showsBot: $showsBot) { _ in }
            }
        } else {
            ContentUnavailableView("No Bot", systemImage: "person.crop.circle.badge.questionmark", description: Text("This bot is no longer on the server."))
        }
    }
}
#endif
