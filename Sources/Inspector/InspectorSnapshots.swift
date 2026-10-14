import SwiftUI

private let ada = Bot(
    name: "ada", displayName: nil, description: "Research assistant. Digs through papers, docs and the web, then writes up what it finds.",
    model: "claude-opus-4-5", isDefault: false, hasAvatar: false,
    canonicalSession: CanonicalSession(
        id: StoredSessionID(rawValue: "s-ada"), resolvedID: StoredSessionID(rawValue: "s-ada"), preview: "Running the migration dry run now.",
        lastActive: .now.addingTimeInterval(-12 * 60), messageCount: 148
    ),
    meta: BotMeta(title: "Ada", shape: "blob", color: "#8b5cf6", expression: "happy"), metaRevision: 1
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
                        .inspectorColumnWidth(min: inspectorWidth.min, ideal: inspectorWidth.ideal, max: inspectorWidth.max)
                }
        }
        #else
        NavigationStack(path: .constant([0])) {
            Text("Ada")
                .navigationDestination(for: Int.self) { _ in inspector }
        }
        #endif
    }

    private let conversations = [
        Conversation(id: StoredSessionID(rawValue: "c1"), title: "Find shared knowledge base endpoint", source: "api_server", startedAt: Date.now.addingTimeInterval(-40 * 60).timeIntervalSince1970, lastActive: Date.now.addingTimeInterval(-35 * 60).timeIntervalSince1970),
        Conversation(id: StoredSessionID(rawValue: "c2"), title: "Compare three weekend flights", source: "tui", startedAt: Date.now.addingTimeInterval(-5 * 3600).timeIntervalSince1970, lastActive: nil),
        Conversation(id: StoredSessionID(rawValue: "c3"), title: "Morning briefing · Oct 13 08:00", source: "cron", startedAt: Date.now.addingTimeInterval(-30 * 3600).timeIntervalSince1970, lastActive: nil),
    ]

    private var inspector: some View {
        BotInspector(
            bot: ada, tab: tab, routines: RoutineStore(fixture: routines), draft: Snapshot.profileDraft, conversations: conversations, models: Snapshot.profileModels,
            isPresented: .constant(true)
        )
            .environment(ChatSessions(fixture: [ada.id: ChatSession(fixture: ada, transcript: Transcript(), todos: adaTodos)]))
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
        ChatScreen(bot: ada, models: models, showsBot: $showsBot)
    }
}
