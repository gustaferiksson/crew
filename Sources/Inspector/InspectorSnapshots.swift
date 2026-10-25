import SwiftUI

private let ada = Bot(
    name: "ada", displayName: nil, description: "Research assistant. Digs through papers, docs and the web, then writes up what it finds.",
    model: "claude-opus-4-5", isDefault: false, hasAvatar: false,
    canonicalSession: CanonicalSession(
        id: StoredSessionID(rawValue: "s-ada"), resolvedID: StoredSessionID(rawValue: "s-ada"), preview: "Running the migration dry run now.",
        lastActive: .now.addingTimeInterval(-12 * 60), messageCount: 148
    ),
    meta: BotMeta(title: "Ada", role: "Research Lead", shape: "blob", color: "#8b5cf6", expression: "happy"), metaRevision: 1
)

private let adaTodos = [
    TodoItem(id: "1", content: "Read the migration guide", status: .completed),
    TodoItem(id: "2", content: "Snapshot the staging database", status: .completed),
    TodoItem(id: "3", content: "Run the migration dry run", status: .inProgress),
    TodoItem(id: "4", content: "Compare row counts before and after", status: .pending),
    TodoItem(id: "5", content: "Write up the rollback plan", status: .pending),
    TodoItem(id: "6", content: "Ping the on-call channel", status: .cancelled),
]

struct InspectorFixtureScreen: View {
    let tab: InspectorTab
    var snapshot: Snapshot?

    private let routines = [
        RoutineJob(
            id: "a1", name: "[bot:ada] Morning briefing", title: "Morning briefing", owner: "ada", prompt: "Summarise overnight papers.",
            schedule: "0 8 * * 1-5", nextRun: .now.addingTimeInterval(16 * 3600), lastRun: .now.addingTimeInterval(-8 * 3600),
            lastStatus: "ok", issue: nil, isPaused: false
        ),
        RoutineJob(
            id: "a2", name: "[bot:ada] Inbox sweep", title: "Inbox sweep", owner: "ada", prompt: "Triage the inbox.",
            schedule: "every 120m", nextRun: .now.addingTimeInterval(40 * 60), lastRun: .now.addingTimeInterval(-80 * 60),
            lastStatus: "error", issue: "Model provider returned 429 Too Many Requests.", isPaused: false
        ),
        RoutineJob(
            id: "a3", name: "[bot:ada] Weekly digest", title: "Weekly digest", owner: "ada", prompt: "Write the weekly digest.",
            schedule: "30 17 * * 5", nextRun: nil, lastRun: .now.addingTimeInterval(-6 * 24 * 3600),
            lastStatus: "ok", issue: nil, isPaused: true
        ),
    ]

    var body: some View {
        #if os(macOS)
        NavigationStack {
            ContentUnavailableView("Chat", systemImage: "bubble.left.and.bubble.right")
                .inspector(isPresented: .constant(true)) {
                    NavigationStack { inspector }
                        .inspectorColumnWidth(min: inspectorWidth.min, ideal: snapshot == .inspectorPasswordsNarrow ? inspectorWidth.min : inspectorWidth.ideal, max: inspectorWidth.max)
                }
        }
        .modifier(PasswordsFixtureSheets(snapshot: snapshot, vault: vault))
        #else
        NavigationStack(path: .constant([0])) {
            Text("Ada")
                .navigationDestination(for: Int.self) { _ in inspector }
        }
        .dynamicTypeSize(snapshot == .inspectorPasswordsNarrow ? .accessibility1 : .large)
        .modifier(PasswordsFixtureSheets(snapshot: snapshot, vault: vault))
        #endif
    }

    @State private var vault = InspectorFixtureScreen.vault(for: Snapshot.requested)

    private static func vault(for snapshot: Snapshot?) -> BotVault {
        let local = { (id: String, host: String, user: String?, created: String, otp: Bool) in
            VaultItem(id: id, kind: "login", label: host, origin: "https://\(host)", createdAt: created, identifier: user, identifierType: user.map { $0.contains("@") ? "email" : "username" }, hasOtp: otp ? true : nil, backend: "local")
        }
        let installed = [VaultSource(name: "local", installed: true, enabled: true, unlocked: true), VaultSource(name: "onepassword", installed: true, enabled: true, unlocked: true)]
        if snapshot == .inspectorPasswordsEmpty {
            return BotVault(fixture: "ada", items: [], sources: [VaultSource(name: "local", installed: true, enabled: true, unlocked: true), VaultSource(name: "onepassword", installed: false, enabled: false, unlocked: false)], tokenSaved: false, terminalBackend: "docker")
        }
        if snapshot == .inspectorPasswordsError {
            return BotVault(fixture: "ada", items: nil, listFailed: true, sources: installed, tokenSaved: true)
        }
        return BotVault(fixture: "ada", items: [
            local("vault_a1", "github.com", "ada@example.com", "2026-09-02T10:00:00+00:00", false),
            local("vault_a2", "accounts.google.com", "ada.lovelace@gmail.com", "2026-09-12T10:00:00+00:00", true),
            local("vault_a3", "www.sj.se", "ada", "2026-08-01T10:00:00+00:00", false),
            local("vault_a4", "www.sj.se", "ada", "2026-10-14T10:00:00+00:00", false),
            local("vault_a5", "booking.long-subdomain-for-reservations.example-travel-platform.com", "ada.lovelace.research.lead@analytical-engines.example.com", "2026-10-01T10:00:00+00:00", false),
            VaultItem(id: "vault_p1", kind: "payment", label: "Shopping card •••• 4242 · www.zalando.se", origin: "https://www.zalando.se", createdAt: "2026-10-01T10:00:00+00:00", backend: "local"),
            VaultItem(id: "op:figma", kind: "login", label: "Figma", origin: "https://www.figma.com", createdAt: "", identifier: "ada@example.com", identifierType: "username", allowedOrigins: ["https://www.figma.com", "https://figma.com"], backend: "onepassword"),
            VaultItem(id: "op:slack", kind: "login", label: "Slack app", origin: "androidapp://com.slack", createdAt: "", backend: "onepassword"),
        ], sources: installed, tokenSaved: true)
    }

    private var shops: ShopList? {
        guard snapshot?.isPasswords == true else { return nil }
        if snapshot == .inspectorPasswordsEmpty { return ShopList(card: MasterCard(label: nil, last4: nil, problem: "missing"), shops: [], terminalBackend: "docker", gate: true) }
        let shop = Shop(id: "v1", origin: "https://www.zalando.se", host: "www.zalando.se", createdAt: Date.now.timeIntervalSince1970 - 9 * 86400, lastPaidAt: nil, stale: false, punycode: false)
        return ShopList(card: MasterCard(label: "Shopping card", last4: "4242", problem: nil), shops: [shop], terminalBackend: "local", gate: true)
    }

    private let conversations = [
        Conversation(id: StoredSessionID(rawValue: "c1"), title: "Find shared knowledge base endpoint", source: "api_server", startedAt: Date.now.addingTimeInterval(-40 * 60).timeIntervalSince1970, lastActive: Date.now.addingTimeInterval(-35 * 60).timeIntervalSince1970),
        Conversation(id: StoredSessionID(rawValue: "c2"), title: "Compare three weekend flights", source: "tui", startedAt: Date.now.addingTimeInterval(-5 * 3600).timeIntervalSince1970, lastActive: nil),
        Conversation(id: StoredSessionID(rawValue: "c3"), title: "Morning briefing · Oct 13 08:00", source: "cron", startedAt: Date.now.addingTimeInterval(-30 * 3600).timeIntervalSince1970, lastActive: nil),
    ]

    private var inspector: some View {
        BotInspector(
            bot: ada, tab: tab, routines: RoutineStore(fixture: snapshot == .inspectorRoutinesEmpty ? [] : routines), draft: Snapshot.profileDraft, conversations: conversations, shops: shops, vault: vault, models: Snapshot.profileModels,
            isPresented: .constant(true)
        )
            .environment(ChatSessions(fixture: [ada.id: ChatSession(fixture: ada, transcript: Transcript(), todos: adaTodos)]))
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("request-log")
                    .accessibilityLabel("Request log")
                    .accessibilityValue(vault.requests.isEmpty ? "none" : vault.requests.joined(separator: ","))
            }
    }
}

private struct PasswordsFixtureSheets: ViewModifier {
    let snapshot: Snapshot?
    let vault: BotVault

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: .constant([.addLogin, .addLoginInvalid, .editLogin].contains(snapshot))) {
                LoginSheet(
                    bot: ada, vault: vault, editing: snapshot == .editLogin ? vault.items?.first : nil,
                    fixture: snapshot == .addLoginInvalid ? LoginEntry(website: "not a website", username: "", password: "") : nil,
                    failure: snapshot == .editLogin ? String(localized: "Couldn't save the login on the server.") : nil
                ) { _ in }
            }
            .sheet(isPresented: .constant(snapshot == .connectOnePassword)) {
                ConnectOnePasswordSheet(bot: ada, vault: BotVault(fixture: "ada", items: [], sources: [VaultSource(name: "onepassword", installed: false, enabled: false, unlocked: false)], tokenSaved: false))
            }
    }
}

struct BotPageFixtureScreen: View {
    @State private var showsBot = true
    @State private var models = Snapshot.profileModels
    @State private var chats = ChatSessions(fixture: [ada.id: ChatSession(fixture: ada, transcript: ChatFixture.history.transcript, todos: adaTodos)])

    var body: some View {
        #if os(iOS)
        NavigationStack(path: .constant([0])) {
            Text("Crew")
                .navigationTitle("Crew")
                .navigationDestination(for: Int.self) { _ in chat }
        }
        .environment(chats)
        #else
        NavigationStack { chat }
            .inspector(isPresented: $showsBot) {
                BotInspector(bot: ada, models: models, isPresented: $showsBot)
                    .inspectorColumnWidth(min: inspectorWidth.min, ideal: inspectorWidth.ideal, max: inspectorWidth.max)
            }
            .environment(chats)
        #endif
    }

    private var chat: some View {
        ChatScreen(bot: ada, models: models, showsBot: $showsBot) { _ in }
    }
}
