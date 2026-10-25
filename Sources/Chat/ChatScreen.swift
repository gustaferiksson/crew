import SwiftUI

struct ChatScreen: View {
    let bot: Bot
    let models: ModelSwitcher
    @Binding var showsBot: Bool
    var focus: SearchFocus?
    let select: (Bot.ID) -> Void

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(ChatSessions.self) private var chats
    @Environment(ChatDrafts.self) private var drafts
    @State private var showsOffline = false
    @State private var addingShop: String?
    @State private var confirming: ChatManagement?
    @State private var outcome: ChatManagementOutcome?

    private var session: ChatSession? {
        chats.sessions[bot.id]
    }

    private var live: Bot {
        bots.bots.first { $0.id == bot.id } ?? bot
    }

    private var status: BotStatus {
        if session?.request != nil { return .waiting(nil) }
        return chats.status(of: bot.id, in: bots)
    }

    private var offlineReason: String? {
        if connection.state == .connected || !showsOffline { return nil }
        if connection.state == .connecting { return String(localized: "Connecting…") }
        return String(localized: "Can't reach \(connection.session?.server.host() ?? String(localized: "the server"))")
    }

    private var shopOffer: String? {
        guard connection.supportsPayments, let session, let turn = session.transcript.turns.last, turn.id != session.dismissedOffer else { return nil }
        return turn.missingShop
    }

    var body: some View {
        ChatView(
            botName: live.title,
            avatar: BotAvatar(bot: live, status: status, photo: bots.photos[bot.id], size: 28),
            transcript: session?.transcript.visible ?? Transcript(),
            emptyState: EmptyView(),
            mentionable: bots.bots.filter { $0.id != bot.id },
            slashCommands: session?.slashCommands ?? [],
            draft: Binding(get: { drafts.texts[bot.id, default: ""] }, set: { drafts.update(bot.id, to: $0) }),
            tray: drafts.tray(for: bot.id),
            request: session?.request,
            payment: session?.request.flatMap { session?.payments[$0.id] },
            paymentNotice: session?.endedPayment,
            shopOffer: shopOffer,
            offlineReason: offlineReason,
            activity: session?.statusLine ?? session?.generatingTool.map { String(localized: "Preparing \($0.replacing("_", with: " "))") },
            models: models,
            focus: focus,
            presentation: Snapshot.requested == .layoutInspector ? ChatPresentation(scrollTarget: "t1") : ChatPresentation(),
            actions: ChatActions(
                send: { session?.send($0, attachments: $1, mentioning: $2, mode: $3) },
                sendHidden: { session?.sendHidden($0) },
                completePath: { await session?.completePath($0) ?? [] },
                stop: { session?.stop() },
                transcribe: transcribe,
                openPersona: { showsBot.toggle() },
                changeModel: { changeModel(to: $0) },
                respond: { session?.respond(to: $0, with: $1) },
                unqueue: { session?.unqueue($0) },
                answer: { session?.answer($0, with: $1) },
                retryPayment: { session?.retryPayment($0) },
                expirePayment: { session?.expirePayment($0) },
                dismissPaymentNotice: { session?.dismissEndedPayment() },
                addShop: { addingShop = $0 },
                dismissShopOffer: { session?.dismissedOffer = session?.transcript.turns.last?.id }
            )
        )
        .environment(\.chatSession, session)
        .sensoryFeedback(.error, trigger: session?.failure) { _, failure in failure != nil }
        .sensoryFeedback(.selection, trigger: models.current) { previous, _ in previous != nil }
        .sheet(item: Binding(get: { addingShop.map(ShopSite.init) }, set: { addingShop = $0?.id })) { site in
            AddShopSheet(profile: bot.name, site: site.id, alreadyAdded: { session?.sendHidden("I added https://\(site.id) to your shops. Continue the purchase.") }) { shop in
                session?.sendHidden("I added \(shop.origin) to your shops. Continue the purchase.")
            }
        }
        #if os(iOS)
        .navigationDestination(isPresented: $showsBot) {
            BotInspector(bot: live, models: models, isPresented: $showsBot)
        }
        #endif
        .task(id: connection.gateway.map(ObjectIdentifier.init)) {
            guard let gateway = connection.gateway else { return }
            chats.open(bot, on: gateway, urlSession: connection.urlSession)
        }
        .task(id: connection.state == .connected) {
            showsOffline = false
            guard connection.state != .connected else { return }
            try? await Task.sleep(for: .seconds(2))
            showsOffline = !Task.isCancelled
        }
        .alert("Change Model?", isPresented: Binding(get: { models.confirmation != nil }, set: { if !$0 { models.confirmation = nil } }), presenting: models.confirmation) { confirmation in
            Button("Cancel", role: .cancel) {}
            Button("Use Model") { changeModel(to: confirmation.choice, confirmation: .confirmed) }
        } message: { confirmation in
            Text(confirmation.message)
        }
        .alert("Couldn't Change Model", isPresented: Binding(get: { models.failure != nil }, set: { if !$0 { models.failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(models.failure ?? "")
        }
        .onChange(of: session?.returned ?? [], initial: true) {
            guard let returned = session?.returned, !returned.isEmpty else { return }
            session?.returned = []
            drafts.update(bot.id, to: ([drafts.texts[bot.id, default: ""]] + returned).filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        .onChange(of: live.canonicalSession?.position, initial: true) {
            bots.markSeen(live)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Chat Options", systemImage: "ellipsis") {
                    Button("Compact Chat…", systemImage: "arrow.down.right.and.arrow.up.left") { confirming = .compact }
                    Button("Start New Chat…", systemImage: "square.and.pencil") { confirming = .newChat }
                }
                .disabled(connection.state != .connected || session?.canManage != true)
            }
        }
        .confirmationDialog(confirming?.title ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { action in
            Button(action.confirm) { manage(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message(botName: live.title))
        }
        .alert(outcome?.title ?? "", isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } }), presenting: outcome) { _ in
            Button("OK", role: .cancel) {}
        } message: { outcome in
            Text(outcome.message)
        }
        .id(bot.id)
    }

    private func manage(_ action: ChatManagement) {
        guard let session else { return }
        Task {
            do {
                if action == .compact {
                    let headline = try await session.compact()
                    outcome = ChatManagementOutcome(title: String(localized: "Chat Compacted"), message: headline ?? "")
                    return
                }
                try await session.startNewChat()
                if let gateway = connection.gateway { await bots.reload(gateway) }
            } catch {
                outcome = ChatManagementOutcome(title: action == .compact ? String(localized: "Couldn't Compact Chat") : String(localized: "Couldn't Start New Chat"), message: error.localizedDescription)
            }
        }
    }

    private func transcribe(_ audio: Data) async throws -> String {
        guard let server = connection.session?.server else { throw HermesError.unauthorized }
        var request = hermesRequest("api/audio/transcribe", on: server, json: ["data_url": "data:audio/m4a;base64,\(audio.base64EncodedString())", "mime_type": "audio/m4a"])
        request.url?.append(queryItems: [URLQueryItem(name: "profile", value: bot.name)])
        request.timeoutInterval = 60
        return try await fetch(request, with: connection.urlSession, as: Transcription.self).transcript
    }

    private func changeModel(to choice: ModelChoice, confirmation: ModelConfirmation = .ask) {
        guard let gateway = connection.gateway else { return }
        Task {
            await models.change(to: choice, confirmation: confirmation, profile: bot.name, via: gateway)
            await bots.reload(gateway)
        }
    }
}

private enum ChatManagement {
    case compact
    case newChat

    var title: LocalizedStringKey {
        self == .compact ? "Compact This Chat?" : "Start a New Chat?"
    }

    var confirm: LocalizedStringKey {
        self == .compact ? "Compact" : "Start New Chat"
    }

    func message(botName: String) -> String {
        self == .compact
            ? String(localized: "\(botName) replaces older messages in its context with a summary, so long chats stay fast and focused.")
            : String(localized: "This chat moves to Other Conversations in \(botName)'s info, and \(botName) starts fresh. Its memory and skills stay.")
    }
}

private struct ChatManagementOutcome {
    let title: String
    let message: String
}

private struct ShopSite: Identifiable {
    let id: String
}
