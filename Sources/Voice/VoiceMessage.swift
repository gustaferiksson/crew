#if os(iOS)
import ActivityKit
import AppIntents
import AVFoundation
import Foundation

enum VoiceStart {
    case started
    case needsPermission
    case needsCrew(String)
    case failed(String)
}

final class VoiceMessage {
    static let shared = VoiceMessage()

    private let dictation = Dictation()
    private var recording: (bot: VoiceBot, server: URL, urlSession: URLSession, activity: Activity<VoiceAttributes>.ID)?

    func start(_ name: String?) async -> VoiceStart {
        guard recording == nil else {
            await send()
            return .started
        }
        guard let (stored, urlSession) = restoredURLSession() else { return .needsCrew(String(localized: "Sign in to Crew first.")) }
        guard let bot = VoiceBot.choose(name, from: VoiceBot.cached()) else { return .needsCrew(String(localized: "Open Crew to load your bots.")) }
        guard AVAudioApplication.shared.recordPermission != .undetermined else { return .needsPermission }
        let activity: Activity<VoiceAttributes>.ID
        do {
            activity = try Activity.request(attributes: VoiceAttributes(bot: bot, startedAt: .now), content: ActivityContent(state: .init(phase: .listening), staleDate: nil)).id
        } catch {
            return .failed(error.localizedDescription)
        }
        await dictation.start { audio in
            var request = hermesRequest("api/audio/transcribe", on: stored.server, json: ["data_url": "data:audio/m4a;base64,\(audio.base64EncodedString())", "mime_type": "audio/m4a"])
            request.url?.append(queryItems: [URLQueryItem(name: "profile", value: bot.name)])
            request.timeoutInterval = 60
            return try await fetch(request, with: urlSession, as: Transcription.self).transcript
        }
        if let failure = dictation.failure {
            await show(.init(phase: .failed, failure: failure), on: activity, ending: .default)
            return .failed(failure)
        }
        recording = (bot, stored.server, urlSession, activity)
        return .started
    }

    func send() async {
        guard let (bot, server, urlSession, activity) = recording else { return }
        recording = nil
        await show(.init(phase: .sending), on: activity, ending: nil)
        await dictation.stop()
        let text = dictation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let failure = dictation.failure {
            return await show(.init(phase: .failed, failure: failure), on: activity, ending: .default)
        }
        guard !text.isEmpty else {
            return await show(.init(phase: .failed, failure: String(localized: "Crew didn't hear anything.")), on: activity, ending: .after(.now + 4))
        }
        guard await submit(text, to: bot, on: server, with: urlSession) else {
            ChatDrafts.shared.update(bot.name, to: [ChatDrafts.shared.texts[bot.name, default: ""], text].filter { !$0.isEmpty }.joined(separator: "\n"))
            return await show(.init(phase: .failed, failure: String(localized: "Couldn't send. It's saved as a draft.")), on: activity, ending: .default)
        }
        await show(.init(phase: .sent), on: activity, ending: .after(.now + 4))
    }

    func cancel() async {
        guard let (_, _, _, activity) = recording else { return }
        recording = nil
        await dictation.cancel()
        await show(.init(phase: .listening), on: activity, ending: .immediate)
    }

    nonisolated private func show(_ state: VoiceAttributes.ContentState, on id: Activity<VoiceAttributes>.ID, ending dismissal: ActivityUIDismissalPolicy?) async {
        guard let activity = Activity<VoiceAttributes>.activities.first(where: { $0.id == id }) else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        guard let dismissal else { return await activity.update(content) }
        await activity.end(content, dismissalPolicy: dismissal)
    }

    private func submit(_ text: String, to bot: VoiceBot, on server: URL, with urlSession: URLSession) async -> Bool {
        guard let gateway = await connectedGateway(to: server, with: urlSession) else { return false }
        let sent: Bool
        do {
            let (_, snapshot) = try await openBotChat(bot.session.map(StoredSessionID.init(rawValue:)), profile: bot.name, via: gateway)
            _ = try await gateway.call("prompt.submit", ["session_id": snapshot.sessionID.rawValue, "text": text], as: JSONValue.self)
            sent = true
        } catch {
            sent = false
        }
        await gateway.disconnect()
        return sent
    }
}

struct CrewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TalkToBotIntent(), phrases: ["Talk to a bot in \(.applicationName)"], shortTitle: "Talk to Bot", systemImageName: "waveform")
    }
}
#endif
