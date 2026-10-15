import SwiftUI

struct GroupAvatar: View {
    let members: [Bot]
    let size: CGFloat

    @Environment(BotStore.self) private var bots

    var body: some View {
        let memberSize = (size * 0.7 / 4).rounded() * 4
        ZStack(alignment: .topLeading) {
            if members.isEmpty {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size / 2))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
            ForEach(Array(members.prefix(2).enumerated()), id: \.element.id) { index, bot in
                BotAvatar(bot: bot, status: .idle, photo: bots.photos[bot.id], size: memberSize)
                    .offset(x: CGFloat(index) * (size - memberSize), y: CGFloat(index) * (size - memberSize))
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(members.map(\.title).formatted(.list(type: .and)))
    }
}

struct GroupChatScreen: View {
    let room: Room
    @Binding var showsInspector: Bool
    let select: (Bot.ID) -> Void

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @State private var session: GroupSession?
    @State private var showsOffline = false

    init(room: Room, showsInspector: Binding<Bool>, session: GroupSession? = nil, select: @escaping (Bot.ID) -> Void) {
        self.room = room
        _showsInspector = showsInspector
        self.select = select
        _session = State(initialValue: session)
    }

    private var members: [Bot] {
        room.members.compactMap { member in bots.bots.first { $0.name == member.profile } }
    }

    private var offlineReason: String? {
        if connection.state == .connected || !showsOffline { return nil }
        if connection.state == .connecting { return String(localized: "Connecting…") }
        return String(localized: "Can't reach \(connection.session?.server.host() ?? String(localized: "the server"))")
    }

    var body: some View {
        ChatView(
            botName: room.name,
            avatar: GroupAvatar(members: members, size: 28),
            transcript: session?.transcript ?? Transcript(),
            mentionable: members,
            features: [],
            request: session?.request,
            offlineReason: offlineReason,
            actions: ChatActions(
                send: { text, _, _, _ in session?.send(text) },
                stop: { session?.stop() },
                openPersona: { showsInspector.toggle() },
                respond: { session?.respond(to: $0, with: $1) }
            )
        )
        #if os(iOS)
        .navigationDestination(isPresented: $showsInspector) {
            GroupInspector(room: room, isPresented: $showsInspector, select: select)
        }
        #endif
        .task(id: connection.gateway.map(ObjectIdentifier.init)) {
            guard let gateway = connection.gateway else { return }
            let session = GroupSession(room: room, gateway: gateway)
            self.session = session
            await session.run()
        }
        .task(id: connection.state == .connected) {
            showsOffline = false
            guard connection.state != .connected else { return }
            try? await Task.sleep(for: .seconds(2))
            showsOffline = !Task.isCancelled
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { session?.failure != nil }, set: { if !$0 { session?.failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session?.failure ?? "")
        }
        .id(room.id)
    }
}
