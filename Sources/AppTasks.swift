import SwiftUI

struct AppTasks: ViewModifier {
    let scenePhase: ScenePhase

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(ChatSessions.self) private var chats
    @Environment(GroupStore.self) private var groups
    @Environment(PushCenter.self) private var push
    @Environment(Scenes.self) private var scenes
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var scene = UUID()

    func body(content: Content) -> some View {
        let owns = scenes.owner == scene
        let isLive = owns && Snapshot.requested == nil
        let gateway = isLive ? connection.gateway.map(ObjectIdentifier.init) : nil
        content
            .onAppear { scenes.claim(scene) }
            .onDisappear { scenes.release(scene) }
            .onChange(of: scenes.owner) { scenes.claim(scene) }
            .task(id: isLive) {
                guard isLive else { return }
                await connection.monitorNetwork()
            }
            .task(id: gateway) {
                guard gateway != nil, let gateway = connection.gateway else { return }
                await bots.run(gateway, urlSession: connection.urlSession)
            }
            .task(id: gateway) {
                guard gateway != nil, let gateway = connection.gateway else { return }
                await groups.run(gateway)
            }
            .task(id: isLive && connection.state == .connected ? push.readiness : nil) {
                guard isLive, connection.state == .connected else { return }
                if [.notDetermined, .provisional].contains(push.authorization) { await push.authorize() }
                await push.register(on: connection)
            }
            .onChange(of: owns && !bots.clearedUnread.isEmpty, initial: true) {
                guard owns else { return }
                let cleared = bots.takeClearedUnread()
                Task {
                    for bot in cleared { await push.announceRead(of: bot, on: connection) }
                }
            }
            .onChange(of: bots.bots) {
                guard owns else { return }
                chats.sync(with: bots.bots)
            }
            .onChange(of: bots.statuses) { old, new in
                guard owns else { return }
                push.notifyLocally(from: old, to: new, bots: bots.bots)
            }
            .onChange(of: owns && connection.state == .signedOut, initial: true) { _, isSignedOut in
                guard isSignedOut else { return }
                bots.reset()
                chats.reset()
                groups.reset()
            }
            .onChange(of: scenePhase) { old, new in
                guard owns else { return }
                bots.isForeground = new == .active
                if new == .active, Snapshot.requested == nil { Task { await push.removeStalePayments() } }
                #if os(iOS)
                if new == .background { return connection.suspend() }
                if old == .background { connection.retry() }
                #endif
            }
            #if os(macOS)
            .onChange(of: owns ? push.pendingRoute : nil, initial: true) {
                guard owns, let route = push.pendingRoute else { return }
                guard scenes.chatWindows.contains(route.profile) else { return openWindow(id: "main") }
                push.pendingRoute = nil
                if route.kind == "payment", let requestID = route.requestID { chats.expectPayment(requestID, for: route.profile) }
                openWindow(value: route.profile)
            }
            .task(id: owns) {
                guard owns else { return }
                await Snapshot.signOutAfterChatWindow(connection, scenes)
            }
            #endif
    }
}
