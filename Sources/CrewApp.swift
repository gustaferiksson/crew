import SwiftUI

@main
struct CrewApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #else
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif
    @State private var connection = Snapshot.requested?.connection ?? Connection()
    @State private var bots = Snapshot.requested?.bots ?? BotStore()
    @State private var chats = Snapshot.requested?.chats ?? ChatSessions()
    @State private var drafts = Snapshot.requested?.drafts ?? ChatDrafts()
    @State private var groups = [.groupChat, .groupWelcome, .groupInspector].contains(Snapshot.requested) ? GroupStore(fixture: [Snapshot.fixtureRoom]) : GroupStore()
    #if os(iOS)
    @State private var updates = UpdateCheck()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    init() {
        if Snapshot.requested != nil { NSApplication.shared.setActivationPolicy(.accessory) }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(connection)
                .environment(bots)
                .environment(chats)
                .environment(drafts)
                .environment(groups)
                .environment(appDelegate.push)
                #if os(macOS)
                .environment(appDelegate.updater)
                #else
                .environment(updates)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await updates.checkOnForeground()
                }
                #endif
                .task {
                    guard let snapshot = Snapshot.requested else { return await connection.monitorNetwork() }
                    await snapshot.capture()
                }
                .task(id: connection.state == .connected ? appDelegate.push.readiness : nil) {
                    guard connection.state == .connected, Snapshot.requested == nil else { return }
                    if [.notDetermined, .provisional].contains(appDelegate.push.authorization) { await appDelegate.push.authorize() }
                    await appDelegate.push.register(on: connection)
                }
                .task {
                    for await bot in bots.unreadCleared.stream {
                        await appDelegate.push.announceRead(of: bot, on: connection)
                    }
                }
                .onChange(of: bots.bots) {
                    chats.sync(with: bots.bots)
                }
                .onChange(of: bots.statuses) { old, new in
                    appDelegate.push.notifyLocally(from: old, to: new, bots: bots.bots)
                }
                .onChange(of: scenePhase) { old, new in
                    bots.isForeground = new == .active
                    if new == .active, Snapshot.requested == nil { Task { await appDelegate.push.removeStalePayments() } }
                    #if os(iOS)
                    if new == .background { return connection.suspend() }
                    if old == .background { connection.retry() }
                    #endif
                }
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                UpdateMenuItems(updater: appDelegate.updater)
            }
        }
        #endif
        #if os(macOS)
        WindowGroup("Chat", for: Bot.ID.self) { $id in
            BotChatWindow(id: id)
                .environment(connection)
                .environment(bots)
                .environment(chats)
                .environment(drafts)
                .environment(groups)
                .environment(appDelegate.push)
                .environment(appDelegate.updater)
        }
        .defaultSize(width: 560, height: 640)
        #endif
    }
}
