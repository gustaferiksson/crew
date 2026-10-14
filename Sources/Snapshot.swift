import SwiftUI

enum Snapshot: String {
    case login
    case loginUnreachable = "login-unreachable"
    case sidebar
    case sidebarFlat = "sidebar-flat"
    case unreachable
    case avatars
    case avatarPicker = "avatar-picker"
    case chat
    case chatHistory = "chat-history"
    case chatTimestamps = "chat-timestamps"
    case chatWorkLog = "chat-worklog"
    case chatQuestion = "chat-question"
    case chatOffline = "chat-offline"
    case chatAttachments = "chat-attachments"
    case chatDictation = "chat-dictation"
    case chatA2UI = "chat-a2ui"
    case chatA2UICards = "chat-a2ui-cards"
    case chatA2UIForm = "chat-a2ui-form"
    case chatA2UITable = "chat-a2ui-table"
    case chatA2UIChart = "chat-a2ui-chart"
    case chatA2UIMap = "chat-a2ui-map"
    case layout
    case layoutInspector = "layout-inspector"
    case inspectorInfo = "inspector-info"
    case inspectorTasks = "inspector-tasks"
    case inspectorRoutines = "inspector-routines"
    case inspectorLook = "inspector-look"
    case profileSkills = "profile-skills"
    case botPage = "bot-page"
    case notifications
    case newBot = "new-bot"

    static let requested = UserDefaults.standard.string(forKey: "snapshot").flatMap(Snapshot.init(rawValue:))

    var chatFixture: ChatFixture? {
        [.chat: .conversation, .chatHistory: .history, .chatTimestamps: .timestamps, .chatWorkLog: .workLog, .chatQuestion: .question, .chatOffline: .offline, .chatAttachments: .attachments, .chatDictation: .dictation, .chatA2UI: .a2ui, .chatA2UICards: .a2uiCards, .chatA2UIForm: .a2uiForm, .chatA2UITable: .a2uiTable, .chatA2UIChart: .a2uiChart, .chatA2UIMap: .a2uiMap][self]
    }

    var inspectorTab: InspectorTab? {
        [.inspectorInfo: .info, .inspectorTasks: .tasks, .inspectorRoutines: .routines][self]
    }

    var connection: Connection {
        let server = URL(string: "https://hermes.example.com")!
        if self == .loginUnreachable {
            return Connection(fixture: .signedOut, server: server, signInError: .unreachable(host: "hermes.example.com"))
        }
        if [.sidebar, .sidebarFlat, .layout, .layoutInspector, .inspectorLook, .profileSkills, .botPage, .notifications, .newBot].contains(self) || chatFixture != nil || inspectorTab != nil { return Connection(fixture: .connected, server: server) }
        if self == .unreachable { return Connection(fixture: .unreachable, server: server) }
        return Connection(fixture: .signedOut, server: server)
    }

    var bots: BotStore {
        let bot = { (name: String, minutesAgo: Double, preview: String, meta: BotMeta) in
            Bot(
                name: name, displayName: nil, description: nil, model: "claude-opus-4-5", isDefault: name == "default", hasAvatar: name == "scout",
                canonicalSession: CanonicalSession(
                    id: StoredSessionID(rawValue: "s-\(name)"), resolvedID: StoredSessionID(rawValue: "s-\(name)"), preview: preview,
                    lastActive: .now.addingTimeInterval(-minutesAgo * 60), messageCount: 12
                ),
                meta: meta, metaRevision: 1
            )
        }
        if self == .sidebarFlat {
            return BotStore(fixture: [
                bot("default", 3, "Done. The release notes are in the shared folder.", BotMeta()),
                bot("scout", 90, "Found three flights under 2 000 kr for the weekend.", BotMeta(title: "Scout", color: "#38bdf8")),
                bot("quill", 60 * 30, "Draft two is ready for review.", BotMeta(title: "Quill", color: "#ec4899")),
            ], statuses: ["scout": .unread])
        }
        return BotStore(fixture: [
            bot("default", 2, "Summarised the inbox: two invoices need approval.", BotMeta(pinned: true)),
            bot("ada", 12, "Running the migration dry run now.", BotMeta(title: "Ada", color: "#8b5cf6", pinned: true)),
            bot("scout", 45, "Found three flights under 2 000 kr for the weekend.", BotMeta(title: "Scout", color: "#38bdf8", pinned: true)),
            bot("forge", 5, "Can I run `npm publish` for 0.4.2?", BotMeta(title: "Forge", color: "#f97316", sectionID: "work", sectionName: "Work")),
            bot("ledger", 60 * 26, "Q3 numbers reconciled against the bank export.", BotMeta(title: "Ledger", color: "#22c55e", sectionID: "work", sectionName: "Work")),
            bot("atlas", 60 * 3, "Tuesday's standup notes are filed.", BotMeta(title: "Atlas", color: "#14b8a6", sectionID: "work", sectionName: "Work")),
            bot("chef", 60 * 24 * 3, "Shopping list for the week is in Reminders.", BotMeta(title: "Chef", color: "#f59e0b", sectionID: "home", sectionName: "Home")),
            bot("quill", 60 * 24 * 12, "Draft two is ready for review.", BotMeta(title: "Quill", color: "#ec4899")),
            bot("ghost", 1, "Hidden bots never show.", BotMeta(title: "Ghost", hidden: true)),
            bot("pixel", 60 * 24 * 40, "Resized the screenshots for the App Store listing.", BotMeta(title: "Pixel", sectionID: "home", sectionName: "Home")),
        ], statuses: ["ada": .working, "forge": .waiting(.approval), "atlas": .unread, "default": .unread, "chef": .failed], photos: Snapshot.samplePhoto.map { ["scout": $0] } ?? [:])
    }

    var selectedBot: Bot.ID? {
        [.layout: "ada", .layoutInspector: "pixel"][self]
    }

    var chats: ChatSessions {
        guard let id = selectedBot, let bot = bots.bots.first(where: { $0.id == id }) else { return ChatSessions() }
        return ChatSessions(fixture: [id: ChatSession(fixture: bot, transcript: ChatFixture.history.transcript, todos: [])])
    }

    static var samplePhoto: Image? {
        let renderer = ImageRenderer(content:
            LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { Image(systemName: "mountain.2.fill").font(.system(size: 40)).foregroundStyle(.white) }
                .frame(width: 96, height: 96)
        )
        renderer.scale = 2
        return renderer.cgImage.map { Image(decorative: $0, scale: 2) }
    }
}

#if os(macOS)
import AppKit

extension Snapshot {
    func capture() async {
        NSApp.appearance = NSAppearance(named: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .darkAqua : .aqua)
        guard let window = NSApp.windows.first(where: \.isVisible) else { exit(1) }
        window.isRestorable = false
        window.setFrameOrigin(NSPoint(x: -4000, y: 0))
        if self == .layoutInspector { window.setContentSize(NSSize(width: 860, height: 640)) }
        try? await Task.sleep(for: .seconds(1.5))
        // cacheDisplay and ImageRenderer skip Liquid Glass; CGWindowListCreateImage is SDK-obsoleted but still exported for own windows.
        typealias CreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"),
              let image = unsafeBitCast(symbol, to: CreateImage.self)(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { exit(1) }
        let output = URL.temporaryDirectory.appending(path: "\(rawValue).png")
        try? png.write(to: output)
        print(output.path(percentEncoded: false))
        exit(0)
    }
}
#else
extension Snapshot {
    func capture() async {
        try? await Task.sleep(for: .seconds(1.5))
        print("ready")
        fflush(stdout)
    }
}
#endif
