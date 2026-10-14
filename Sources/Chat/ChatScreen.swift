import SwiftUI

struct ChatScreen: View {
    let bot: Bot
    let models: ModelSwitcher
    @Binding var showsBot: Bool

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(ChatSessions.self) private var chats
    @State private var showsOffline = false

    private var session: ChatSession? {
        chats.sessions[bot.id]
    }

    private var live: Bot {
        bots.bots.first { $0.id == bot.id } ?? bot
    }

    private var status: BotStatus {
        if session?.request != nil { return .waiting(nil) }
        if session?.isRunning == true { return .working }
        return chats.status(of: bot.id, in: bots)
    }

    private var offlineReason: String? {
        if connection.state == .connected || !showsOffline { return nil }
        if connection.state == .connecting { return String(localized: "Connecting…") }
        return String(localized: "Can't reach \(connection.session?.server.host() ?? String(localized: "the server"))")
    }

    var body: some View {
        ChatView(
            botName: live.title,
            avatar: BotAvatar(bot: live, status: status, photo: bots.photos[bot.id], size: 28),
            transcript: session?.transcript ?? Transcript(),
            request: session?.request,
            offlineReason: offlineReason,
            activity: session?.statusLine ?? session?.generatingTool.map { String(localized: "Preparing \($0.replacing("_", with: " "))") },
            models: models,
            presentation: Snapshot.requested == .layoutInspector ? ChatPresentation(scrollTarget: "t1") : ChatPresentation(),
            actions: ChatActions(
                send: { session?.send($0, attachments: $1, mode: $2) },
                stop: { session?.stop() },
                transcribe: transcribe,
                openPersona: { showsBot.toggle() },
                changeModel: { changeModel(to: $0) },
                respond: { session?.respond(to: $0, with: $1) },
                answer: { session?.answer($0, with: $1) }
            )
        )
        .environment(\.chatSession, session)
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
        .onChange(of: live.canonicalSession?.position, initial: true) {
            bots.markSeen(live)
        }
        .id(bot.id)
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
