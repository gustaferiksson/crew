import Testing

private let choice = ModelChoice(provider: "openai-codex", model: "gpt-6-astra")

private func bot(_ name: String, model: String? = nil, provider: String? = nil, isDefault: Bool = false, hidden: Bool = false) -> Bot {
    var bot = Bot(name: name, displayName: nil, description: nil, model: model, isDefault: isDefault, hasAvatar: false, canonicalSession: nil, meta: BotMeta(title: name.capitalized, hidden: hidden ? true : nil), metaRevision: nil)
    bot.provider = provider
    return bot
}

private final class Server {
    var calls: [(bot: String, confirmation: ModelConfirmation)] = []
    var failing: [String: String] = [:]
    var asks: Set<String> = []
    var onCall: (String) -> Void = { _ in }

    var apply: ModelForAllBots.Apply {
        { bot, _, confirmation in
            self.calls.append((bot, confirmation))
            self.onCall(bot)
            if let message = self.failing[bot] { throw GatewayError.rpc(code: 4064, message: message) }
            if self.asks.contains(bot), confirmation == .ask { return .needsConfirmation("This model may train on your data.") }
            return .applied
        }
    }

    var names: [String] { calls.map(\.bot) }
}

@MainActor private func run(_ bots: [Bot], on server: Server, roster: (() -> [Bot])? = nil) async -> ModelForAllBots {
    let run = ModelForAllBots()
    run.choice = choice
    await run.start(on: bots, apply: server.apply, roster: roster ?? { bots })
    return run
}

@MainActor @Test func everyBotChangesWithTheDefaultBotFirst() async {
    let server = Server()
    let result = await run([bot("ada"), bot("default", isDefault: true), bot("scout")], on: server)

    #expect(server.names == ["default", "ada", "scout"])
    #expect(result.phase == .finished)
    #expect(result.changed == 3 && result.total == 3 && result.failures.isEmpty)
}

@MainActor @Test func hiddenBotsAndBotsAlreadyOnTheModelAreSkipped() async {
    let server = Server()
    let bots = [
        bot("ada"), bot("ghost", hidden: true), bot("same", model: "gpt-6-astra", provider: "openai-codex"),
        bot("otherProvider", model: "gpt-6-astra", provider: "nous"), bot("unknown", model: "gpt-6-astra"),
    ]
    _ = await run(bots, on: server)

    #expect(server.names == ["ada", "otherProvider", "unknown"])
    #expect(ModelForAllBots.hiddenCount(in: bots) == 1)
}

@MainActor @Test func aHiddenDefaultBotStillChanges() async {
    let server = Server()
    _ = await run([bot("ada"), bot("default", isDefault: true, hidden: true)], on: server)

    #expect(server.names == ["default", "ada"])
}

@MainActor @Test func aFailedBotIsReportedAndTryAgainResendsOnlyIt() async {
    let server = Server()
    server.failing["vera"] = "Model not available for this bot."
    let bots = [bot("ada"), bot("vera"), bot("scout")]
    let result = await run(bots, on: server)

    #expect(result.changed == 2 && result.total == 3)
    #expect(result.failures == [.init(bot: "Vera", message: "Model not available for this bot.")])
    #expect(result.remaining.map(\.name) == ["vera"])

    server.calls = []
    server.failing = [:]
    await result.run(apply: server.apply, roster: { bots })

    #expect(server.names == ["vera"])
    #expect(result.changed == 3 && result.failures.isEmpty && result.remaining.isEmpty)
}

@MainActor @Test func aConfirmationFromTheFirstBotWritesNothingUntilConfirmed() async {
    let server = Server()
    server.asks = ["ada", "scout"]
    let bots = [bot("ada"), bot("vera"), bot("scout")]
    let result = await run(bots, on: server)

    #expect(result.phase == .confirming("This model may train on your data."))
    #expect(server.names == ["ada"])

    await result.confirm(apply: server.apply, roster: { bots })

    #expect(server.calls.dropFirst().allSatisfy { $0.confirmation == .confirmed })
    #expect(result.changed == 3 && result.failures.isEmpty)
}

@MainActor @Test func aLaterBotAskingAgainFailsThatBotOnly() async {
    let server = Server()
    server.asks = ["scout"]
    let result = await run([bot("ada"), bot("scout"), bot("vera")], on: server)

    #expect(result.phase == .finished)
    #expect(result.changed == 2)
    #expect(result.failures.map(\.bot) == ["Scout"])
}

@MainActor @Test func stoppingFinishesTheBotInFlightThenHalts() async {
    let server = Server()
    let run = ModelForAllBots()
    run.choice = choice
    server.onCall = { if $0 == "scout" { run.stop() } }
    let bots = [bot("ada"), bot("scout"), bot("vera"), bot("quill")]
    await run.start(on: bots, apply: server.apply, roster: { bots })

    #expect(server.names == ["ada", "scout"])
    #expect(run.changed == 2 && run.wasStopped)
    #expect(run.remaining.map(\.name) == ["vera", "quill"])
    #expect(run.phase == .finished)
}

@MainActor @Test func aLostConnectionEndsTheRunWithAResumableRest() async {
    let run = ModelForAllBots()
    run.choice = choice
    let bots = [bot("ada"), bot("scout"), bot("vera")]
    let lost: ModelForAllBots.Apply = { name, _, _ in
        if name == "scout" { throw GatewayError.disconnected }
        return .applied
    }
    await run.start(on: bots, apply: lost, roster: { bots })

    #expect(run.changed == 1)
    #expect(run.remaining.map(\.name) == ["scout", "vera"])
}

@MainActor @Test func botsAddedDuringTheRunAreCountedButNotChanged() async {
    let server = Server()
    let bots = [bot("ada"), bot("scout")]
    let result = await run(bots, on: server, roster: { bots + [bot("new"), bot("hiddenNew", hidden: true)] })

    #expect(server.names == ["ada", "scout"])
    #expect(result.added == 1)
}
