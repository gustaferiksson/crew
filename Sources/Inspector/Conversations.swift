import SwiftUI

nonisolated struct Conversation: Decodable, Identifiable, Hashable, Sendable {
    let id: StoredSessionID
    let title: String?
    let source: String?
    let startedAt: Double
    let lastActive: Double?
}

nonisolated private struct ConversationPage: Decodable, Sendable {
    let sessions: [Conversation]
}

nonisolated func otherConversations(of bot: Bot, on server: URL, with urlSession: URLSession) async throws -> [Conversation] {
    var request = hermesRequest("api/sessions", on: server)
    request.url?.append(queryItems: [
        URLQueryItem(name: "profile", value: bot.name),
        URLQueryItem(name: "order", value: "recent"),
        URLQueryItem(name: "limit", value: "50"),
        URLQueryItem(name: "archived", value: "include"),
    ])
    let canonical = [bot.canonicalSession?.id, bot.canonicalSession?.resolvedID]
    return try await fetch(request, with: urlSession, as: ConversationPage.self).sessions
        .filter { $0.title != "Bot Chat" && !canonical.contains($0.id) }
}

struct ConversationList: View {
    let conversations: [Conversation]?
    let failure: String?
    let open: (Conversation) -> Void

    var body: some View {
        if let conversations, conversations.isEmpty {
            Text("No other conversations")
                .foregroundStyle(.secondary)
        } else if let conversations {
            ForEach(conversations) { conversation in
                Button {
                    open(conversation)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title ?? String(localized: "Untitled"))
                                .lineLimit(1)
                            Text("\((conversation.source ?? "").replacing("_", with: " ")) · \(Date(timeIntervalSince1970: conversation.lastActive ?? conversation.startedAt), format: .relative(presentation: .named))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #if os(macOS)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.tertiary)
                        #endif
                    }
                    .contentShape(.rect)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #else
                .tint(.primary)
                #endif
            }
        } else if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

struct ConversationTranscript: View {
    let bot: Bot
    let conversation: Conversation

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(\.dismiss) private var dismiss
    @State private var session: ChatSession?
    @State private var focus: SearchFocus?
    @State private var draft = ""
    @State private var showsOffline = false
    @State private var tray = AttachmentTray()

    init(bot: Bot, conversation: Conversation, focus: String? = nil) {
        self.bot = bot
        self.conversation = conversation
        _focus = State(initialValue: focus.map { SearchFocus(bot: bot.id, snippet: $0) })
    }

    private var offlineReason: String? {
        if connection.state == .connected || !showsOffline { return nil }
        if connection.state == .connecting { return String(localized: "Connecting…") }
        return String(localized: "Can't reach \(connection.session?.server.host() ?? String(localized: "the server"))")
    }

    var body: some View {
        NavigationStack {
            ChatView(
                botName: bot.title,
                title: conversation.title ?? String(localized: "Untitled"),
                avatar: BotAvatar(bot: bot, status: .idle, photo: bots.photos[bot.id], size: 28),
                transcript: session?.transcript.visible ?? Transcript(),
                emptyState: emptyState,
                mentionable: bots.bots.filter { $0.id != bot.id },
                slashCommands: session?.slashCommands ?? [],
                draft: $draft,
                tray: tray,
                request: session?.request,
                payment: session?.request.flatMap { session?.payments[$0.id] },
                paymentNotice: session?.endedPayment,
                offlineReason: offlineReason,
                activity: session?.statusLine ?? session?.generatingTool.map { String(localized: "Preparing \($0.replacing("_", with: " "))") },
                focus: focus,
                actions: ChatActions(
                    send: { session?.send($0, attachments: $1, mentioning: $2, mode: $3) },
                    sendHidden: { session?.sendHidden($0) },
                    completePath: { await session?.completePath($0) ?? [] },
                    stop: { session?.stop() },
                    respond: { session?.respond(to: $0, with: $1) },
                    unqueue: { session?.unqueue($0) },
                    answer: { session?.answer($0, with: $1) },
                    retryPayment: { session?.retryPayment($0) },
                    expirePayment: { session?.expirePayment($0) },
                    dismissPaymentNotice: { session?.dismissEndedPayment() }
                )
            )
            .environment(\.chatSession, session)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
        .task(id: connection.gateway.map(ObjectIdentifier.init)) {
            if Snapshot.requested != nil {
                session = ChatSession(fixture: bot, transcript: ChatFixture.history.transcript, todos: [])
                return
            }
            guard let gateway = connection.gateway else { return }
            let session = ChatSession(bot: bot, resuming: conversation.id, gateway: gateway, urlSession: connection.urlSession)
            self.session = session
            await session.run()
        }
        .task(id: connection.state == .connected) {
            showsOffline = false
            guard connection.state != .connected else { return }
            try? await Task.sleep(for: .seconds(2))
            showsOffline = !Task.isCancelled
        }
        .onChange(of: session?.returned ?? [], initial: true) {
            guard let returned = session?.returned, !returned.isEmpty else { return }
            session?.returned = []
            draft = ([draft] + returned).filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if let failure = session?.failure {
            ContentUnavailableView("Couldn't Load Conversation", systemImage: "exclamationmark.triangle", description: Text(failure))
        } else {
            ProgressView()
        }
    }
}
