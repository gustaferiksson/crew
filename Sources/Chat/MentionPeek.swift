import SwiftUI

struct MentionPeek: View {
    let bot: Bot
    let turnID: Turn.ID
    let showChat: () -> Void

    @Environment(BotStore.self) private var roster
    @Environment(ChatSessions.self) private var chats
    @Environment(\.chatSession) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var exchange: MentionExchange? {
        session.flatMap { mentionExchange(with: bot.id, from: turnID, in: $0.transcript) }
    }

    private var live: Bot { roster.bots.first { $0.id == bot.id } ?? bot }

    private var status: BotStatus { chats.status(of: bot.id, in: roster) }

    private var about: String? {
        [live.meta.description, live.description].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BotAvatar(bot: bot, status: status, photo: roster.photos[live.id], size: 44)
                VStack(alignment: .leading) {
                    Text(live.title)
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
                            section("Message to \(live.title)", text: exchange.message)
                        }
                        outcome(exchange.outcome)
                    } else {
                        section("Recent", date: live.canonicalSession?.lastActive, text: live.canonicalSession?.preview ?? String(localized: "No messages yet"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 20)
                .padding(16)
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 16)
                        .accessibilityHidden(true)
                }
                #if os(iOS)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
                #else
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 20))
                #endif
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows \(live.title)'s chat")
            if let about {
                Text(about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(20)
        .foregroundStyle(Color.primary)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Show Chat", showChat)
    }

    private var statusText: Text {
        let handle = Text(verbatim: "@\(live.handle)")
        if case .waiting(let kind) = status {
            return Text("\(handle) · \(Text(kind == .approval ? "Needs approval" : "Waiting for you").foregroundStyle(.orange))")
        }
        if status == .working {
            return Text("\(handle) · \(Text(chats.sessions[live.id]?.statusLine ?? String(localized: "Working")).foregroundStyle(.green))")
        }
        if status == .failed {
            return Text("\(handle) · \(Text("Failed").foregroundStyle(.red))")
        }
        guard exchange == nil, let date = live.canonicalSession?.lastActive else { return handle }
        return Text("\(handle) · Active \(date, format: .relative(presentation: .named))")
    }

    @ViewBuilder
    private func outcome(_ outcome: MentionExchange.Outcome) -> some View {
        if case .replied(let reply, let date) = outcome {
            section("\(live.title)'s reply", date: date, text: reply)
        } else if outcome == .awaiting, status == .working {
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .phaseAnimator(reduceMotion ? [1] : [1, 0.4]) { dot, opacity in
                        dot.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 1)
                    }
                Text("Waiting for \(live.title)")
            }
            .foregroundStyle(.secondary)
        } else if outcome == .awaiting {
            Text("No reply yet")
                .foregroundStyle(.secondary)
        } else if outcome == .sending {
            Text("Sending…")
                .foregroundStyle(.secondary)
        } else if outcome == .delivered {
            Text("Delivered. The answer is in \(live.title)'s chat.")
                .foregroundStyle(.secondary)
        } else if outcome == .relayed {
            Text("Sent through Hermes Desktop. The reply will show up there.")
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
            Text(text)
                .lineLimit(4)
        }
    }
}

#if os(iOS)
struct MentionSheet: View {
    let bot: Bot
    let turnID: Turn.ID

    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = Snapshot.requested == .chatMentionChat ? .large : .medium
    @State private var models = ModelSwitcher()
    @State private var showsBot = false

    var body: some View {
        Group {
            if detent == .large {
                NavigationStack {
                    ChatScreen(bot: bot, models: models, showsBot: $showsBot) { _ in }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                            }
                        }
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
            .inspector(isPresented: $showsBot) {
                BotInspector(bot: bot, models: models, isPresented: $showsBot)
                    .inspectorColumnWidth(min: inspectorWidth.min, ideal: inspectorWidth.ideal, max: inspectorWidth.max)
            }
        } else {
            ContentUnavailableView("No Bot", systemImage: "person.crop.circle.badge.questionmark", description: Text("This bot is no longer on the server."))
        }
    }
}
#endif
