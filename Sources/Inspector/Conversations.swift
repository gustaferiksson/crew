import SwiftUI

nonisolated struct Conversation: Decodable, Identifiable, Hashable, Sendable {
    let id: StoredSessionID
    let title: String?
    let source: String?
    let startedAt: Double
    let lastActive: Double?
}

nonisolated private struct ConversationPage: Decodable, Sendable {
    let sessions: [Conversation]
}

nonisolated func otherConversations(of bot: Bot, on server: URL, with urlSession: URLSession) async throws -> [Conversation] {
    var request = hermesRequest("api/sessions", on: server)
    request.url?.append(queryItems: [
        URLQueryItem(name: "profile", value: bot.name),
        URLQueryItem(name: "order", value: "recent"),
        URLQueryItem(name: "limit", value: "50"),
    ])
    let canonical = [bot.canonicalSession?.id, bot.canonicalSession?.resolvedID]
    return try await fetch(request, with: urlSession, as: ConversationPage.self).sessions
        .filter { $0.title != "Bot Chat" && !canonical.contains($0.id) }
}

struct ConversationList: View {
    let conversations: [Conversation]?
    let failure: String?
    let open: (Conversation) -> Void

    var body: some View {
        if let conversations, conversations.isEmpty {
            Text("No other conversations")
                .foregroundStyle(.secondary)
        } else if let conversations {
            VStack(spacing: 8) {
                ForEach(conversations) { conversation in
                    if conversation.id != conversations.first?.id {
                        Divider()
                    }
                    Button {
                        open(conversation)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title ?? String(localized: "Untitled"))
                                    .lineLimit(1)
                                Text("\((conversation.source ?? "").replacing("_", with: " ")) · \(Date(timeIntervalSince1970: conversation.lastActive ?? conversation.startedAt), format: .relative(presentation: .named))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

struct ConversationTranscript: View {
    let bot: Bot
    let conversation: Conversation

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(\.dismiss) private var dismiss
    @State private var transcript: Transcript?
    @State private var failure: String?
    @State private var surfaces = SurfaceStore()
    @State private var expandedTurns: Set<Turn.ID> = []
    @State private var expandedWork: Set<WorkItem.ID> = []
    @State private var expandedRuns: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if let transcript {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            ForEach(transcript.turns) { turn in
                                TurnView(
                                    turn: turn,
                                    surfaces: surfaces,
                                    activity: nil,
                                    reveal: 0,
                                    timestampWidth: 40,
                                    mentionable: bots.bots.filter { $0.id != bot.id },
                                    expandedTurns: $expandedTurns,
                                    expandedWork: $expandedWork,
                                    expandedRuns: $expandedRuns
                                )
                            }
                        }
                        .padding(16)
                    }
                    .defaultScrollAnchor(.bottom)
                } else if let failure {
                    ContentUnavailableView("Couldn't Load Conversation", systemImage: "exclamationmark.triangle", description: Text(failure))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(conversation.title ?? String(localized: "Untitled"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
        .task {
            guard let server = connection.session?.server else { return }
            do {
                let loaded = Transcript(history: try await history(of: conversation.id, profile: bot.name, on: server, with: connection.urlSession))
                surfaces.sync(loaded)
                transcript = loaded
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
