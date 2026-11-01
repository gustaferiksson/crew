#if os(iOS)
import AppIntents
import Foundation

struct AskBotIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Bot"
    static let description = IntentDescription("Sends a message to a bot and returns its answer.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Bot")
    var bot: BotEntity

    @Parameter(title: "Message", requestValueDialog: "What do you want to ask?")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$bot) \(\.$message)")
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let deadline = ContinuousClock.now + .seconds(20)
        guard let (stored, urlSession) = restoredURLSession() else {
            throw BotTurnFailure(errorDescription: String(localized: "Sign in to Crew first."))
        }
        guard let gateway = await connectedGateway(to: stored.server, with: urlSession) else {
            throw saveDraft()
        }
        let answer: BotAnswer
        do {
            let known = VoiceBot.cached().first { $0.name == bot.id }?.session.map(StoredSessionID.init(rawValue:))
            let (_, snapshot) = try await openBotChat(known, profile: bot.id, via: gateway)
            let params = ["session_id": snapshot.sessionID.rawValue, "text": message]
            answer = try await BotAnswer.wait(in: snapshot.sessionID, for: gateway.events(), after: { try await gateway.call("prompt.submit", params, as: SubmitStatus.self) }, until: deadline)
        } catch let failure as BotTurnFailure {
            await gateway.disconnect()
            throw BotTurnFailure(errorDescription: failure.errorDescription ?? String(localized: "\(bot.title) couldn't answer."))
        } catch {
            await gateway.disconnect()
            throw saveDraft()
        }
        await gateway.disconnect()
        guard case .reply(let reply) = answer else {
            return .result(value: "", dialog: "Sent. You'll get a notification when \(bot.title) replies.")
        }
        let speech = BotAnswer.speech(from: reply)
        guard let first = speech.split(separator: "\n").first else {
            return .result(value: "", dialog: "\(bot.title) sent a card. Open Crew to see it.")
        }
        let dialog = first.count < speech.count ? String(localized: "\(String(first)) The rest is in Crew.") : speech
        return .result(value: speech, dialog: IntentDialog(stringLiteral: dialog))
    }

    @MainActor
    private func saveDraft() -> BotTurnFailure {
        let draft = ChatDrafts.shared.texts[bot.id, default: ""]
        ChatDrafts.shared.update(bot.id, to: [draft, message].filter { !$0.isEmpty }.joined(separator: "\n"))
        return BotTurnFailure(errorDescription: String(localized: "Couldn't send. It's saved as a draft."))
    }
}

struct OpenBotChatIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Bot Chat"
    static let description = IntentDescription("Opens a bot's chat in Crew.")

    @Parameter(title: "Bot")
    var target: BotEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "crew://chat")!.appending(path: target.id)))
    }
}
#endif
