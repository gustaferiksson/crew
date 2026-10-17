import SwiftUI

struct RootView: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        Group {
            if let fixture = Snapshot.requested?.chatFixture {
                ChatFixtureScreen(fixture: fixture)
            } else if let tab = Snapshot.requested?.inspectorTab {
                InspectorFixtureScreen(tab: tab)
            } else if let snapshot = Snapshot.requested, snapshot.isShops {
                ShopsFixtureScreen(snapshot: snapshot)
            } else if Snapshot.requested == .botPage {
                BotPageFixtureScreen()
            } else if Snapshot.requested == .notifications {
                NotificationSettings()
                    .environment(PushCenter(fixture: .registered(apnsConfigured: true), plugin: PluginStatus(pluginVersion: "0.2.0", installId: "fixture", apnsConfigured: true, http2: true, devices: 2)))
            } else if Snapshot.requested == .avatars {
                AvatarGallery()
            } else if Snapshot.requested == .avatarPicker {
                AvatarPickerFixture()
            } else if Snapshot.requested == .profileSkills {
                ProfileSkillsFixture()
            } else if Snapshot.requested == .inspectorLook {
                LookFixture()
            } else if Snapshot.requested == .newBot {
                NewBotFixture()
            } else if [.groupChat, .groupWelcome].contains(Snapshot.requested) {
                GroupChatFixtureScreen()
            } else if Snapshot.requested == .groupInspector {
                GroupInspectorFixtureScreen()
            } else if let snapshot = Snapshot.requested, snapshot.isChatWindow {
                #if os(macOS)
                BotChatWindow(id: snapshot.selectedBot)
                #endif
            } else if connection.state == .signedOut {
                LoginView()
            } else {
                BotsView()
            }
        }
    }
}
