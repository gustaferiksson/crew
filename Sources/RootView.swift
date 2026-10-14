import SwiftUI

struct RootView: View {
    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(ChatSessions.self) private var chats

    var body: some View {
        Group {
            if let fixture = Snapshot.requested?.chatFixture {
                ChatFixtureScreen(fixture: fixture)
            } else if let tab = Snapshot.requested?.inspectorTab {
                InspectorFixtureScreen(tab: tab)
            } else if Snapshot.requested == .botPage {
                BotPageFixtureScreen()
            } else if Snapshot.requested == .notifications {
                NotificationSettings()
                    .environment(PushCenter(fixture: .notInstalled))
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
            } else if connection.state == .signedOut {
                LoginView()
            } else {
                BotsView()
            }
        }
        .onChange(of: connection.state == .signedOut, initial: true) { _, isSignedOut in
            guard isSignedOut else { return }
            bots.reset()
            chats.reset()
        }
    }
}
