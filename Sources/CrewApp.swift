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
    @State private var drafts = Snapshot.requested?.drafts ?? .shared
    @State private var groups = [.groupChat, .groupWelcome, .groupInspector, .sidebarCompact].contains(Snapshot.requested) ? GroupStore(fixture: [Snapshot.fixtureRoom]) : GroupStore()
    @State private var scenes = Scenes()
    #if os(iOS)
    @State private var updates = UpdateCheck()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    init() {
        if Snapshot.requested != nil, !Snapshot.isInteractive { NSApplication.shared.setActivationPolicy(.accessory) }
    }
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("Crew", id: "main") {
            crewEnvironment(RootView().task { await Snapshot.requested?.capture() })
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                UpdateMenuItems(updater: appDelegate.updater)
            }
            CommandGroup(replacing: .newItem) {
                NewChatCommands(connection: connection, groups: groups, scenes: scenes)
                Divider()
                OpenChatWindowCommand()
            }
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                InspectorCommand()
            }
        }
        WindowGroup("Chat", for: Bot.ID.self) { $id in
            crewEnvironment(BotChatWindow(id: id))
        }
        .defaultSize(width: 560, height: 640)
        .commandsRemoved()
        Settings {
            crewEnvironment(SettingsView())
        }
        #else
        WindowGroup {
            crewEnvironment(RootView().task { await Snapshot.requested?.capture() })
                .environment(\.openURL, .inAppBrowser)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await updates.checkOnForeground()
                }
        }
        #endif
    }

    private func crewEnvironment(_ content: some View) -> some View {
        content
            .modifier(AppTasks(scenePhase: scenePhase))
            .environment(connection)
            .environment(bots)
            .environment(chats)
            .environment(drafts)
            .environment(groups)
            .environment(scenes)
            .environment(appDelegate.push)
            #if os(macOS)
            .environment(appDelegate.updater)
            #else
            .environment(updates)
            #endif
    }
}
