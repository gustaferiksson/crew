import SwiftUI

nonisolated struct SessionMatch: Decodable, Sendable {
    let sessionId: StoredSessionID
    let lineageRoot: StoredSessionID?
    let title: String?
    let snippet: String
    let role: String?
    let lastActive: Double?
    let sessionStarted: Double?
    let startedAt: Double?
}

nonisolated struct SessionMatchPage: Decodable, Sendable {
    let results: [SessionMatch]
}

nonisolated struct MessageHit: Identifiable, Hashable, Sendable {
    let bot: Bot.ID
    let session: StoredSessionID
    let title: String?
    let snippet: String
    let speaker: String?
    let isInBotChat: Bool
    let conversationDate: Date

    var id: String { "\(bot)/\(session.rawValue)" }

    init?(bot: Bot, match: SessionMatch) {
        let raw = match.snippet.replacing(/>>>|<<</, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = raw.trimmingPrefix("...").trimmingCharacters(in: .whitespacesAndNewlines)
        let isCutNotice = match.role == "user" && raw.hasPrefix("...") && plain.hasSuffix("]")
        guard ["user", "assistant"].contains(match.role), !isCutNotice,
              !["[IMPORTANT: Background process", "[System:", "<a2ui-action>"].contains(where: { plain.hasPrefix($0) })
        else { return nil }
        let agentMessage = match.role == "user" ? AgentMessage(plain) : nil
        self.bot = bot.id
        session = match.sessionId
        title = match.title
        snippet = agentMessage == nil ? match.snippet : match.snippet.replacing(/(?s)^\s*(?:Message from [^:\n]*?:\s*|\[Message from agent '[^']*'\]\s*)/, with: "", maxReplacements: 1)
        speaker = agentMessage?.sender ?? (match.role == "user" ? String(localized: "You") : nil)
        let canonical = [bot.canonicalSession?.id, bot.canonicalSession?.resolvedID].compactMap(\.self)
        isInBotChat = canonical.contains(match.sessionId) || match.lineageRoot.map(canonical.contains) == true || match.title == "Bot Chat"
        conversationDate = Date(timeIntervalSince1970: match.lastActive ?? match.sessionStarted ?? match.startedAt ?? 0)
    }

    func highlighted(_ query: String) -> AttributedString {
        let flat = flattenedSnippet(snippet)
        let words = query.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        let pattern = (try? Regex<Substring>(words.joined(separator: "|")))?.ignoresCase()
        let marked = flat.contains(">>>") || words.isEmpty ? flat : pattern.map { flat.replacing($0) { ">>>\($0.output)<<<" } } ?? flat
        let lead = marked.range(of: ">>>").map { marked[..<$0.lowerBound] } ?? ""
        let kept = lead.count > 32 ? lead.suffix(24).drop { !$0.isWhitespace }.drop { $0.isWhitespace || $0 == "·" } : lead
        var result = AttributedString(speaker.map { "\($0): " } ?? "")
        var rest = kept.count < lead.count ? Substring("…" + kept + marked[lead.endIndex...]) : Substring(marked)
        while let match = rest.firstMatch(of: />>>(.*?)<<</) {
            result += AttributedString(rest[..<match.range.lowerBound])
            var term = AttributedString(match.1)
            term.foregroundColor = .primary
            term.font = .subheadline.weight(.semibold)
            result += term
            rest = rest[match.range.upperBound...]
        }
        return result + AttributedString(rest)
    }
}

struct SearchFocus: Equatable {
    let id = UUID()
    let bot: Bot.ID
    let snippet: String
}

nonisolated func flattenedSnippet(_ snippet: String) -> String {
    let unfenced = snippet.range(of: "```").map { "\(snippet[..<$0.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)) ..." } ?? snippet
    return unfenced
        .replacing(/(?m)^[ \t]*(?:#{1,6}|>|[-*+]|\d+\.)[ \t]+/, with: "")
        .replacing(/\[[ xX]\][ \t]*/, with: "")
        .replacing(/\*\*|`/, with: "")
        .replacing(/\s*\n\s*/, with: " · ")
        .replacing(/\s+/, with: " ")
        .replacing("...", with: "…")
        .trimmingCharacters(in: .whitespaces)
}

nonisolated func searchMessages(of bot: Bot, matching query: String, on server: URL, with urlSession: URLSession) async throws -> [MessageHit] {
    var request = hermesRequest("api/sessions/search", on: server)
    request.url?.append(queryItems: [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "profile", value: bot.name),
        URLQueryItem(name: "limit", value: "5"),
        URLQueryItem(name: "exclude_sources", value: "subagent,tool"),
    ])
    return try await fetch(request, with: urlSession, as: SessionMatchPage.self).results.compactMap { MessageHit(bot: bot, match: $0) }
}

extension Transcript {
    nonisolated func turn(matching snippet: String) -> Turn? {
        let collapse = { (text: String) in text.replacing(/\s+/, with: " ").lowercased() }
        let pieces = snippet.replacing(">>>", with: "").replacing("<<<", with: "")
            .components(separatedBy: "...")
            .map { collapse($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }
        let terms = snippet.matches(of: />>>(.*?)<<</).map { collapse(String($0.1)) }
        let texts = turns.reversed().map { turn in
            let work = turn.work.map { item in
                switch item.kind {
                case .thinking(let text), .note(let text): text
                case .tool(let call): [call.arguments, call.result ?? ""].joined(separator: " ")
                }
            }
            let parts = [turn.prompt?.text, turn.reply, turn.agentMessage?.body, turn.hiddenText, turn.notice].compactMap(\.self) + work
            return (turn: turn, text: collapse(parts.joined(separator: " ")))
        }
        if let found = pieces.lazy.compactMap({ piece in texts.first { $0.text.contains(piece) }?.turn }).first { return found }
        guard !terms.isEmpty else { return nil }
        return texts.first { candidate in terms.allSatisfy { candidate.text.contains($0) } }?.turn
    }
}

@Observable
final class MessageSearch {
    enum Phase {
        case idle, searching, done, offline
    }

    private(set) var hits: [MessageHit] = []
    private(set) var phase = Phase.idle
    private(set) var failed = 0
    private(set) var searched = 0
    private var completed: [String]?
    private let fixture: [MessageHit]?

    init(fixture: [MessageHit]? = nil) {
        self.fixture = fixture
    }

    static func isSearchable(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    func run(_ query: String, in bots: [Bot], on server: URL?, with urlSession: URLSession) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = bots.filter { $0.meta.hidden != true }
        let key = [query, server?.absoluteString ?? ""] + targets.map(\.id)
        guard key != completed || phase != .done else { return }
        guard Self.isSearchable(query) else {
            hits = []
            phase = .idle
            return
        }
        if let fixture {
            hits = fixture.filter { $0.snippet.replacing(/>>>|<<</, with: "").localizedStandardContains(query) }
            phase = .done
            return
        }
        guard let server else {
            hits = []
            phase = .offline
            return
        }
        phase = .searching
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        var fresh: [MessageHit]?
        var failures = 0
        await withTaskGroup(of: [MessageHit]?.self) { group in
            var pending = targets.makeIterator()
            for _ in 0..<4 {
                guard let bot = pending.next() else { break }
                group.addTask { try? await searchMessages(of: bot, matching: query, on: server, with: urlSession) }
            }
            for await found in group {
                guard !Task.isCancelled else { return }
                if let bot = pending.next() {
                    group.addTask { try? await searchMessages(of: bot, matching: query, on: server, with: urlSession) }
                }
                guard let found else {
                    failures += 1
                    continue
                }
                fresh = ((fresh ?? []) + found).sorted { $0.conversationDate > $1.conversationDate }
                hits = fresh ?? []
            }
        }
        guard !Task.isCancelled else { return }
        hits = fresh ?? []
        failed = failures
        searched = targets.count
        completed = key
        phase = .done
    }
}
