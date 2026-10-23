import SwiftUI

enum Snapshot: String {
    case login
    case loginUnreachable = "login-unreachable"
    case sidebar
    case sidebarFlat = "sidebar-flat"
    case sidebarDraft = "sidebar-draft"
    case sidebarSearch = "sidebar-search"
    case searchResult = "search-result"
    case unreachable
    case avatars
    case avatarPicker = "avatar-picker"
    case chat
    case chatHistory = "chat-history"
    case chatSelection = "chat-selection"
    case chatTimestamps = "chat-timestamps"
    case chatWorkLog = "chat-worklog"
    case chatQuestion = "chat-question"
    case chatQuestions = "chat-questions"
    case chatQuestionsSnacks = "chat-questions-snacks"
    case chatOffline = "chat-offline"
    case chatAttachments = "chat-attachments"
    case chatDictation = "chat-dictation"
    case chatMentions = "chat-mentions"
    case composerLine = "composer-line"
    case composerLines = "composer-lines"
    case composerRunning = "composer-running"
    case composerRunningText = "composer-running-text"
    case chatSteer = "chat-steer"
    case chatSteerTaken = "chat-steer-taken"
    case chatWaiting = "chat-waiting"
    case chatMentionPeek = "chat-mention-peek"
    case chatMentionChat = "chat-mention-chat"
    case chatAgentMessage = "chat-agent-message"
    case chatDeliveryFailure = "chat-delivery-failure"
    case chatA2UI = "chat-a2ui"
    case chatA2UICards = "chat-a2ui-cards"
    case chatA2UIForm = "chat-a2ui-form"
    case chatA2UITable = "chat-a2ui-table"
    case chatA2UIChart = "chat-a2ui-chart"
    case chatA2UIMap = "chat-a2ui-map"
    case layout
    case layoutInspector = "layout-inspector"
    case chatWindow = "chat-window"
    case chatWindowInspector = "chat-window-inspector"
    case chatWindowMissing = "chat-window-missing"
    case inspectorInfo = "inspector-info"
    case inspectorTasks = "inspector-tasks"
    case inspectorRoutines = "inspector-routines"
    case inspectorLook = "inspector-look"
    case profileSkills = "profile-skills"
    case botPage = "bot-page"
    case notifications
    case newBot = "new-bot"
    case groupChat = "group-chat"
    case groupWelcome = "group-welcome"
    case groupInspector = "group-inspector"
    case chatPayment = "chat-payment"
    case chatPaymentHolding = "chat-payment-holding"
    case chatPaymentApproved = "chat-payment-approved"
    case chatPaymentLoading = "chat-payment-loading"
    case chatPaymentFailed = "chat-payment-failed"
    case chatPaymentUnverified = "chat-payment-unverified"
    case chatPaymentPunycode = "chat-payment-punycode"
    case chatPaymentCountdown = "chat-payment-countdown"
    case chatPaymentNotice = "chat-payment-notice"
    case chatPaymentOffer = "chat-payment-offer"
    case chatPaymentOfferHistory = "chat-payment-offer-history"
    case chatPaymentReceipts = "chat-payment-receipts"
    case inspectorShops = "inspector-shops"
    case inspectorShopsEmpty = "inspector-shops-empty"
    case inspectorShopsNoCard = "inspector-shops-no-card"
    case inspectorShopsSeveral = "inspector-shops-several"
    case addShop = "add-shop"
    case addShopError = "add-shop-error"
    case inspectorShopsUpdateError = "inspector-shops-update-error"
    case inspectorShopsCodeMismatch = "inspector-shops-code-mismatch"
    case addCard = "add-card"
    case addCardInvalid = "add-card-invalid"
    case replaceCard = "replace-card"
    case addCardHTTP = "add-card-http"
    case addCardCover = "add-card-cover"
    case inspectorPasswords = "inspector-passwords"
    case inspectorPasswordsEmpty = "inspector-passwords-empty"
    case inspectorPasswordsError = "inspector-passwords-error"
    case inspectorPasswordsOffline = "inspector-passwords-offline"
    case inspectorPasswordsNarrow = "inspector-passwords-narrow"
    case addLogin = "add-login"
    case addLoginInvalid = "add-login-invalid"
    case editLogin = "edit-login"
    case connectOnePassword = "connect-1password"

    static let requested = UserDefaults.standard.string(forKey: "snapshot").flatMap(Snapshot.init(rawValue:))
    static let isInteractive = UserDefaults.standard.bool(forKey: "uiTest")
    static let scrollsToBottom = requested != nil && UserDefaults.standard.bool(forKey: "snapshotBottom")

    var chatFixture: ChatFixture? {
        [.chat: .conversation, .chatHistory: .history, .chatSelection: .history, .chatTimestamps: .timestamps, .chatWorkLog: .workLog, .chatQuestion: .question, .chatQuestions: .questions, .chatQuestionsSnacks: .questionsSnacks, .chatOffline: .offline, .chatAttachments: .attachments, .chatDictation: .dictation, .chatMentions: .mentions, .composerLine: .composerLine, .composerLines: .composerLines, .composerRunning: .composerRunning, .composerRunningText: .composerRunningText, .chatSteer: .steer, .chatSteerTaken: .steerTaken, .chatWaiting: .waiting, .chatMentionPeek: .mentions, .chatMentionChat: .mentions, .chatAgentMessage: .agentMessage, .chatDeliveryFailure: .deliveryFailure, .chatA2UI: .a2ui, .chatA2UICards: .a2uiCards, .chatA2UIForm: .a2uiForm, .chatA2UITable: .a2uiTable, .chatA2UIChart: .a2uiChart, .chatA2UIMap: .a2uiMap, .chatPayment: .payment, .chatPaymentHolding: .paymentHolding, .chatPaymentApproved: .paymentApproved, .chatPaymentLoading: .paymentLoading, .chatPaymentFailed: .paymentFailed, .chatPaymentUnverified: .paymentUnverified, .chatPaymentPunycode: .paymentPunycode, .chatPaymentCountdown: .paymentCountdown, .chatPaymentNotice: .paymentNotice, .chatPaymentOffer: .paymentOffer, .chatPaymentOfferHistory: .paymentOfferHistory, .chatPaymentReceipts: .paymentReceipts][self]
    }

    var isShops: Bool {
        [.inspectorShops, .inspectorShopsEmpty, .inspectorShopsNoCard, .inspectorShopsSeveral, .addShop, .addShopError, .inspectorShopsUpdateError, .inspectorShopsCodeMismatch].contains(self) || isCardSheet
    }

    var isCardSheet: Bool {
        [.addCard, .addCardInvalid, .replaceCard, .addCardHTTP, .addCardCover].contains(self)
    }

    var inspectorTab: InspectorTab? {
        if isPasswords { return .passwords }
        return [.inspectorInfo: .info, .inspectorTasks: .tasks, .inspectorRoutines: .routines][self]
    }

    var isPasswords: Bool {
        [.inspectorPasswords, .inspectorPasswordsEmpty, .inspectorPasswordsError, .inspectorPasswordsOffline, .inspectorPasswordsNarrow, .addLogin, .addLoginInvalid, .editLogin, .connectOnePassword].contains(self)
    }

    var connection: Connection {
        let server = URL(string: "https://hermes.example.com")!
        if self == .loginUnreachable {
            return Connection(fixture: .signedOut, server: server, signInError: .unreachable(host: "hermes.example.com"))
        }
        if isPasswords {
            return Connection(fixture: self == .inspectorPasswordsOffline ? .unreachable : .connected, server: server, crewPush: PluginStatus(pluginVersion: "0.6.0", installId: "fixture", apnsConfigured: true, http2: true, devices: 2, features: ["payments", "card", "card_vault"], gate: true))
        }
        if isShops || chatFixture?.isPayment == true {
            return Connection(fixture: .connected, server: self == .addCardHTTP ? URL(string: "http://hermes.local:9119")! : server, crewPush: PluginStatus(pluginVersion: "0.5.0", installId: "fixture", apnsConfigured: true, http2: true, devices: 2, features: ["payments", "card"], gate: true))
        }
        if [.sidebar, .sidebarFlat, .sidebarDraft, .sidebarSearch, .searchResult, .layout, .layoutInspector, .chatWindow, .chatWindowInspector, .chatWindowMissing, .inspectorLook, .profileSkills, .botPage, .notifications, .newBot, .groupChat, .groupWelcome, .groupInspector].contains(self) || chatFixture != nil || inspectorTab != nil { return Connection(fixture: .connected, server: server) }
        if self == .unreachable { return Connection(fixture: .unreachable, server: server) }
        return Connection(fixture: .signedOut, server: server)
    }

    var bots: BotStore {
        let bot = { (name: String, minutesAgo: Double, preview: String, meta: BotMeta) in
            Bot(
                name: name, displayName: nil, description: name == "scout" ? "Finds flights, trains and hotels, and keeps an eye on prices." : nil, model: "claude-opus-4-5", isDefault: name == "default", hasAvatar: name == "scout",
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
            bot("ada", 12, "Running the migration dry run now.", BotMeta(title: "Ada Lovelace", role: "Head of Research and Analytics", color: "#8b5cf6", pinned: true)),
            bot("scout", 45, "Found three flights under 2 000 kr for the weekend.", BotMeta(title: "Scout", role: "Travel Planner", color: "#38bdf8", pinned: true)),
            bot("forge", 5, "Can I run `npm publish` for 0.4.2?", BotMeta(title: "Forge", role: "Release Engineer", color: "#f97316", sectionID: "work", sectionName: "Work")),
            bot("ledger", 60 * 26, "Q3 numbers reconciled against the bank export.", BotMeta(title: "Ledger", role: "Bookkeeper and Finance Controller", color: "#22c55e", sectionID: "work", sectionName: "Work")),
            bot("atlas", 60 * 3, "Tuesday's standup notes are filed.", BotMeta(title: "Atlas", color: "#14b8a6", sectionID: "work", sectionName: "Work")),
            bot("chef", 60 * 24 * 3, "Shopping list for the week is in Reminders.", BotMeta(title: "Chef", color: "#f59e0b", sectionID: "home", sectionName: "Home")),
            bot("quill", 60 * 24 * 12, "Draft two is ready for review.", BotMeta(title: "Quill", color: "#ec4899")),
            bot("ghost", 1, "Hidden bots never show.", BotMeta(title: "Ghost", hidden: true)),
            bot("pixel", 60 * 24 * 40, "Resized the screenshots for the App Store listing.", BotMeta(title: "Pixel", sectionID: "home", sectionName: "Home")),
        ], statuses: ["scout": .working, "forge": .waiting(.approval), "atlas": .unread, "default": .unread, "chef": .failed], photos: Snapshot.samplePhoto.map { ["scout": $0] } ?? [:])
    }

    var drafts: ChatDrafts {
        ChatDrafts(fixture: self == .sidebarDraft ? [
            "ledger": "Can you also check the trains from Bodø on Friday, and whether the night train has sleeper cabins left?",
            "forge": "Yes, go ahead",
        ] : [:])
    }

    var selectedBot: Bot.ID? {
        [.layout: "ada", .layoutInspector: "pixel", .searchResult: "default", .chatWindow: "ada", .chatWindowInspector: "ada", .chatWindowMissing: "gone"][self]
    }

    var searchQuery: String? {
        [.sidebarSearch: "boat", .searchResult: "boat"][self]
    }

    var searchFocus: SearchFocus? {
        guard self == .searchResult, let hit = searchHits?.first else { return nil }
        return SearchFocus(bot: hit.bot, snippet: hit.snippet)
    }

    var searchHits: [MessageHit]? {
        guard searchQuery != nil else { return nil }
        let roster = bots.bots
        let hit = { (bot: String, session: String, title: String, role: String, hoursAgo: Double, snippet: String) in
            roster.first { $0.id == bot }.flatMap { found in
                MessageHit(bot: found, match: SessionMatch(
                    sessionId: StoredSessionID(rawValue: session), lineageRoot: nil, title: title, snippet: snippet, role: role,
                    lastActive: Date.now.addingTimeInterval(-hoursAgo * 3600).timeIntervalSince1970, sessionStarted: nil, startedAt: nil
                ))
            }
        }
        return [
            hit("default", "s-default", "Bot Chat", "assistant", 0.05, "...Trail shoes with grip; the rock is slick when wet\n- Headlamp, daylight is only about **8 hours**\n- Dry bag for the >>>boat<<< trip\n\n> Book the >>>boat<<< early; tours thin out after the season ends."),
            hit("scout", "s-scout-reine", "Ferries around Reine", "assistant", 20, "The Reine to Vindstad >>>boat<<< runs twice a day until the end of October, so plan the Bunes beach hike around the 10:15 departure..."),
            hit("chef", "s-chef", "Bot Chat", "user", 50, "Pack something for a >>>boat<<< picnic on Saturday, nothing that needs a fridge"),
            hit("ledger", "s-ledger-q3", "Q3 expenses", "assistant", 24 * 9, "...the >>>boat<<< rental in Lofoten (1 450 kr) is filed under travel, not entertainment."),
        ].compactMap(\.self)
    }

    var chats: ChatSessions {
        if self == .chatMentionChat, let scout = bots.bots.first(where: { $0.id == "scout" }) {
            let asked = Date.now.addingTimeInterval(-5 * 60)
            let turn = Turn(
                id: "s1", prompt: Prompt(text: "Keep an eye on flight prices to Lofoten for March.", sentAt: asked.addingTimeInterval(-3600)),
                reply: "Watching. The cheapest right now is SAS on Friday at 07:10 for 1 840 kr.", status: .complete,
                startedAt: asked.addingTimeInterval(-3600), finishedAt: asked.addingTimeInterval(-3590)
            )
            return ChatSessions(fixture: ["scout": ChatSession(fixture: scout, transcript: Transcript(turns: [turn]), todos: [])])
        }
        guard let id = selectedBot ?? (self == .sidebarSearch ? "default" : nil), let bot = bots.bots.first(where: { $0.id == id }) else { return ChatSessions() }
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
    static func signOutAfterChatWindow(_ connection: Connection, _ scenes: Scenes) async {
        guard isInteractive, UserDefaults.standard.bool(forKey: "signOutAfterChatWindow") else { return }
        while scenes.chatWindows.isEmpty || NSApp.windows.filter(\.isVisible).count > 1, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        connection.endFixtureSession()
    }

    func capture() async {
        NSApp.appearance = NSAppearance(named: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .darkAqua : .aqua)
        let height = UserDefaults.standard.double(forKey: "snapshotHeight")
        guard !Snapshot.isInteractive else {
            if height > 0, let window = NSApp.windows.first(where: \.isVisible) { window.setContentSize(NSSize(width: window.contentRect(forFrameRect: window.frame).width, height: height)) }
            return
        }
        guard let window = NSApp.windows.first(where: \.isVisible) else { exit(1) }
        window.isRestorable = false
        window.setFrameOrigin(NSPoint(x: -4000, y: 0))
        if self == .layoutInspector { window.setContentSize(NSSize(width: 860, height: 640)) }
        if self == .chatSelection { window.setContentSize(NSSize(width: 860, height: 900)) }
        if self == .chatTimestamps { window.setContentSize(NSSize(width: 560, height: 900)) }
        if [.chatWindow, .chatWindowMissing].contains(self) { window.setContentSize(NSSize(width: 560, height: 640)) }
        if self == .chatWindowInspector { window.setContentSize(NSSize(width: 900, height: 640)) }
        if height > 0 { window.setContentSize(NSSize(width: window.contentRect(forFrameRect: window.frame).width, height: height)) }
        try? await Task.sleep(for: .seconds(1.5))
        if self == .chatSelection, let reply = window.contentView.map(replyTextViews)?.first(where: { $0.string.contains("Merino") }) {
            let text = reply.string as NSString
            let start = text.range(of: "Expect").location
            reply.setSelectedRange(NSRange(location: start, length: NSMaxRange(text.range(of: "Merino top")) - start))
            try? await Task.sleep(for: .seconds(0.5))
        }
        if UserDefaults.standard.bool(forKey: "measure") { await measure(window) }
        // cacheDisplay and ImageRenderer skip Liquid Glass; CGWindowListCreateImage is SDK-obsoleted but still exported for own windows.
        typealias CreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"),
              let image = unsafeBitCast(symbol, to: CreateImage.self)(.null, .optionIncludingWindow, CGWindowID((window.attachedSheet ?? window).windowNumber), [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { exit(1) }
        let output = URL.temporaryDirectory.appending(path: "\(rawValue).png")
        try? png.write(to: output)
        print(output.path(percentEncoded: false))
        exit(0)
    }

    private func replyTextViews(in view: NSView) -> [ReplyTextView] {
        ((view as? ReplyTextView).map { [$0] } ?? []) + view.subviews.flatMap(replyTextViews)
    }

    private func measure(_ window: NSWindow) async {
        func splitControllers(_ view: NSView) -> [NSSplitViewController] {
            (((view as? NSSplitView)?.delegate as? NSSplitViewController).map { [$0] } ?? []) + view.subviews.flatMap(splitControllers)
        }
        let controllers = window.contentView.map(splitControllers) ?? []
        controllers.forEach { $0.splitView.autosaveName = nil }
        window.setFrameAutosaveName("")
        func report(_ label: String) async {
            window.setContentSize(window.contentMinSize)
            try? await Task.sleep(for: .seconds(1))
            let columns = controllers.map { $0.splitViewItems.map { $0.isCollapsed ? "-" : "\(Int($0.viewController.view.frame.width))" }.joined(separator: "|") }
            let items = (window.toolbar?.items ?? []).compactMap { item in
                item.view.map { view in
                    let rect = view.convert(view.bounds, to: nil)
                    let hit = window.contentView?.superview?.hitTest(NSPoint(x: rect.midX, y: rect.midY))
                    return "\(item.label)@\(Int(rect.minX))\(hit?.isDescendant(of: view) == true ? "" : " (blocked)")"
                }
            }
            print("MEASURE \(rawValue) \(label): min \(Int(window.contentMinSize.width))x\(Int(window.contentMinSize.height)), max \(window.contentMaxSize.width > 10_000 ? "none" : "\(window.contentMaxSize)"), columns \(columns), toolbar \(items)")
        }
        await report("initial")
        NotificationCenter.default.post(name: .measureInspector, object: true)
        try? await Task.sleep(for: .seconds(1.5))
        await report("inspector open")
        controllers.last?.toggleSidebar(nil)
        try? await Task.sleep(for: .seconds(1.5))
        await report("inspector open, sidebar toggled")
        NotificationCenter.default.post(name: .measureInspector, object: false)
        try? await Task.sleep(for: .seconds(1.5))
        await report("inspector closed, sidebar toggled")
        window.setContentSize(NSSize(width: 4000, height: 3000))
        try? await Task.sleep(for: .seconds(1))
        print("MEASURE \(rawValue) largest \(Int(window.contentLayoutRect.width))x\(Int(window.contentLayoutRect.height))")
        exit(0)
    }
}

extension Notification.Name {
    static let measureInspector = Notification.Name("measureInspector")
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
