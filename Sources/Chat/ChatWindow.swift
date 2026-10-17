#if os(macOS)
import SwiftUI

struct BotChatWindow: View {
    let id: Bot.ID?

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(PushCenter.self) private var push
    @Environment(Scenes.self) private var scenes
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var models = ModelSwitcher()
    @State private var showsBot = Snapshot.requested == .chatWindowInspector

    var body: some View {
        let bot = bots.bots.first { $0.id == id }
        Group {
            if let bot {
                NavigationStack {
                    ChatScreen(bot: bot, models: models, showsBot: $showsBot) { _ in }
                }
                .inspector(isPresented: $showsBot) {
                    BotInspector(bot: bot, models: models, isPresented: $showsBot)
                        .inspectorColumnWidth(min: inspectorWidth.min, ideal: inspectorWidth.ideal, max: inspectorWidth.max)
                }
            } else if !bots.isLoaded {
                ProgressView()
            } else {
                ContentUnavailableView("No Bot", systemImage: "person.crop.circle.badge.questionmark", description: Text("This bot is no longer on the server."))
            }
        }
        .task(id: [bot?.id, bot?.model, connection.gateway.map { "\(ObjectIdentifier($0))" }]) {
            let switcher = ModelSwitcher()
            models = switcher
            guard let bot, let gateway = connection.gateway else { return }
            await switcher.load(profile: bot.name, via: gateway)
        }
        .onAppear {
            if let id { scenes.chatWindows.insert(id) }
        }
        .onDisappear {
            if let id { scenes.chatWindows.remove(id) }
        }
        .onChange(of: appearsActive, initial: true) {
            if appearsActive, let id { push.show(id) }
        }
        .onChange(of: connection.state == .signedOut, initial: true) { _, isSignedOut in
            guard isSignedOut else { return }
            openWindow(id: "main")
            dismissWindow()
        }
    }
}

struct OpenChatWindowCommand: View {
    @FocusedValue(\.selectedBot) private var bot
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open in New Window") {
            if let bot { openWindow(value: bot) }
        }
        .keyboardShortcut("o")
        .disabled(bot == nil)
    }
}

extension FocusedValues {
    @Entry var selectedBot: Bot.ID?
}
#endif
