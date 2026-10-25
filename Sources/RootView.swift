import SwiftUI

struct RootView: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        Group {
            if let fixture = Snapshot.requested?.chatFixture {
                ChatFixtureScreen(fixture: fixture)
            } else if let tab = Snapshot.requested?.inspectorTab {
                InspectorFixtureScreen(tab: tab, snapshot: Snapshot.requested)
            } else if let snapshot = Snapshot.requested, snapshot.isShops {
                ShopsFixtureScreen(snapshot: snapshot)
            } else if Snapshot.requested == .botPage || Snapshot.requested == .chatOptions {
                BotPageFixtureScreen()
            } else if Snapshot.requested == .notifications {
                NotificationSettings()
                    .environment(Snapshot.fixturePush)
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
            } else if Snapshot.requested == .newGroup {
                NewGroupSheet { _ in }
            } else if [.groupChat, .groupWelcome].contains(Snapshot.requested) {
                GroupChatFixtureScreen()
            } else if Snapshot.requested == .groupInspector {
                GroupInspectorFixtureScreen()
            } else if let snapshot = Snapshot.requested, [.chatWindow, .chatWindowInspector, .chatWindowMissing].contains(snapshot) {
                #if os(macOS)
                BotChatWindow(id: snapshot.selectedBot)
                #endif
            } else if Snapshot.requested?.isSettings == true {
                #if os(macOS)
                SettingsOpener()
                #endif
            } else if connection.state == .signedOut {
                LoginView()
            } else {
                BotsView()
            }
        }
    }
}

#if os(macOS)
private struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 200, height: 100)
            .onAppear { openSettings() }
    }
}
#endif
