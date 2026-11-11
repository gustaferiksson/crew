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
            } else if Snapshot.requested == .chatContext {
                ContextSheet(usage: ContextUsage(used: 462_300, window: 1_000_000), loadBreakdown: { [
                    ContextCategory(id: "system_prompt", label: "System prompt", tokens: 4_657),
                    ContextCategory(id: "tool_definitions", label: "Tool definitions", tokens: 6_022),
                    ContextCategory(id: "memory", label: "Memory", tokens: 1_840),
                    ContextCategory(id: "conversation", label: "Conversation", tokens: 449_781),
                ] }, compact: {})
            } else if Snapshot.requested == .contextRings {
                HStack(spacing: 24) {
                    ForEach([0.04, 0.28, 0.46, 0.75, 1], id: \.self) { ContextRing(fraction: $0) }
                }
                .padding(40)
            } else if Snapshot.requested == .notifications {
                NotificationSettings()
                    .environment(Snapshot.fixturePush)
            } else if Snapshot.requested == .avatars {
                AvatarGallery()
            } else if Snapshot.requested == .voiceActivity {
                #if os(iOS)
                VoiceActivityFixture()
                #endif
            } else if Snapshot.requested == .avatarEyes {
                LivingEyesFixture()
            } else if Snapshot.requested == .avatarPicker {
                AvatarPickerFixture()
            } else if Snapshot.requested == .profileSkills {
                ProfileSkillsFixture()
            } else if Snapshot.requested == .inspectorLook {
                LookFixture()
            } else if Snapshot.requested == .newBot {
                NewBotFixture()
            } else if Snapshot.requested == .newBotAdvanced {
                NewBotAdvancedFixture()
            } else if Snapshot.requested == .newGroup {
                NewGroupSheet { _ in }
            } else if [.groupChat, .groupChatPaused, .groupChatContext, .groupChatRoutine, .groupChatReply, .groupChatReplyPinned, .groupWelcome].contains(Snapshot.requested) {
                GroupChatFixtureScreen()
            } else if [.groupInspector, .groupInspectorMembers].contains(Snapshot.requested) {
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
