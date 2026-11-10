import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())
private let now = Date(timeIntervalSince1970: 1_794_340_800)
private let british = Locale(identifier: "en_GB")
private let nous = [ModelProvider(slug: "nous", name: "Nous Portal", models: ["anthropic/claude-sonnet-4.5", "anthropic/claude-haiku-4.5"])]

private var stockholm: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    return calendar
}

private func contract() throws -> [String: JSONValue] {
    try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: fixtures.appending(path: "chat.limit-failures.contract.v0.23.0.json")))
}

@MainActor private func failedTurn(_ shape: String) throws -> Turn {
    var start = Transcript()
    start.begin(prompt: "Draft the Q3 board update.")
    let session = ChatSession(fixture: crewTest, transcript: start, todos: [])
    session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(#"{"type":"message.start","payload":{}}"#.utf8)))
    session.apply(try JSONDecoder().decode(GatewayEvent.self, from: JSONEncoder().encode(try #require(try contract()[shape]))))
    return try #require(session.transcript.turns.last)
}

@MainActor @Test func aUsageLimitSaysWhatRanOutAndWhenItResets() throws {
    let turn = try failedTurn("usage_window")
    let limit = try #require(turn.limit)

    #expect(turn.status == .error)
    #expect(turn.reply == "")
    #expect(limit.sentence(at: now, calendar: stockholm, locale: british) == "Your Nous Portal daily limit is reached. It resets at 23:00.")
    #expect(limit.sentence(at: now, calendar: stockholm, locale: Locale(identifier: "en_US")) == "Your Nous Portal daily limit is reached. It resets at 11:00\u{202F}PM.")
}

@MainActor @Test func aUsageLimitOffersASuggestedModelTheSwitcherHas() throws {
    let limit = try #require(try failedTurn("usage_window").limit)

    #expect(limit.switchable(among: nous, current: ModelChoice(provider: "nous", model: "anthropic/claude-sonnet-4.5"))?.label == "Claude Haiku 4.5")
    #expect(limit.switchable(among: nous, current: ModelChoice(provider: "nous", model: "anthropic/claude-haiku-4.5")) == nil)
    #expect(limit.switchable(among: [ModelProvider(slug: "openai-codex", name: "Codex", models: ["anthropic/claude-haiku-4.5"])], current: nil) == nil)
}

@MainActor @Test func aRateLimitSaysHowSoonItResets() throws {
    let turn = try failedTurn("rate_limit")
    let limit = try #require(turn.limit)

    #expect(turn.reply == "")
    #expect(limit.sentence(at: now, calendar: stockholm, locale: british) == "Your Anthropic rate limit is reached. It resets in 12 minutes.")
    #expect(limit.sentence(at: now.addingTimeInterval(13 * 60), calendar: stockholm, locale: british) == "Your Anthropic rate limit was reached.")
    #expect(limit.switchable(among: nous, current: nil) == nil)
}

@MainActor @Test func aFailureWithoutASurfaceKeepsItsErrorText() throws {
    let turn = try failedTurn("no_surface")

    #expect(turn.status == .error)
    #expect(turn.limit == nil)
    #expect(turn.failure == "HTTP 500: upstream connect error")
}

@MainActor @Test func aHistoryReloadKeepsTheLimit() throws {
    let live = Transcript(turns: [try failedTurn("usage_window")])
    var reloaded = Transcript(turns: [Turn(id: live.turns[0].id, prompt: live.turns[0].prompt, status: .complete, startedAt: live.turns[0].startedAt)])
    reloaded.keepFailures(from: live)

    #expect(reloaded.turns.last?.limit == live.turns[0].limit)
}

@Test func aReopenedChatShowsTheLimitFromItsFailedTurnRow() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([HistoryRow].self, from: JSONEncoder().encode(try #require(try contract()["history"])))
    let turn = try #require(Transcript(history: rows).turns.last)
    let limit = try #require(turn.limit)

    #expect(turn.prompt?.text == "Draft the Q3 board update.")
    #expect(turn.status == .error)
    #expect(turn.reply == "")
    #expect(limit.sentence(at: now, calendar: stockholm, locale: british) == "Your Nous Portal daily limit is reached. It resets at 23:00.")
    #expect(limit.switchable(among: nous, current: ModelChoice(provider: "nous", model: "anthropic/claude-sonnet-4.5"))?.model == "anthropic/claude-haiku-4.5")
}

@Test func aFailedTurnRowWithoutALimitKeepsItsText() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([HistoryRow].self, from: Data(contentsOf: fixtures.appending(path: "scenarios/delivery-failure/crew-test-peer.history.json")))
    let turn = try #require(Transcript(history: rows).turns.first { $0.reply.hasPrefix("Your request was not processed.") })

    #expect(turn.limit == nil)
    #expect(turn.status == .complete)
}

@Test func aLaterResetNamesTheDay() throws {
    let tomorrow = #"{"code":"usage_window","provider_label":"Nous Portal","usage_limit":{"limit_name":"weekly","resets_at_ms":1794384000000}}"#
    let nextWeek = #"{"code":"usage_window","usage_limit":{"limit_name":"weekly","resets_at_ms":1794783600000}}"#
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let byTomorrow = try #require(LimitFailure(try decoder.decode(LimitFailure.Surface.self, from: Data(tomorrow.utf8))))
    let byNextWeek = try #require(LimitFailure(try decoder.decode(LimitFailure.Surface.self, from: Data(nextWeek.utf8))))

    #expect(byTomorrow.sentence(at: now, calendar: stockholm, locale: british) == "Your Nous Portal weekly limit is reached. It resets tomorrow at 9:00.")
    #expect(byNextWeek.sentence(at: now, calendar: stockholm, locale: british) == "Your weekly limit is reached. It resets Monday 16 Nov at 0:00.")
    #expect(LimitFailure(try decoder.decode(LimitFailure.Surface.self, from: Data(#"{"code":"auth","provider_label":"Anthropic"}"#.utf8))) == nil)
}
