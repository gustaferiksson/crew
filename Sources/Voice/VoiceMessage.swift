#if os(iOS)
import ActivityKit
import AppIntents
import AVFoundation
import Foundation
import Observation
import os

let voiceLog = Logger(subsystem: "dev.gustaf.crew", category: "voice")

enum VoiceStart {
    case started
    case needsPermission
    case needsCrew(String)
    case failed(String)
}

@MainActor
@Observable
final class VoiceMessage {
    static let shared = Snapshot.requested?.voiceFixture.map { VoiceMessage(fixture: $0) } ?? VoiceMessage()

    let dictation: Dictation
    private(set) var attributes: VoiceAttributes?
    private(set) var state = VoiceAttributes.ContentState(phase: .recording)
    @ObservationIgnored private var recording: (bot: VoiceBot, server: URL, urlSession: URLSession)?
    @ObservationIgnored private var activity: Activity<VoiceAttributes>.ID?

    init() {
        dictation = Dictation()
        dictation.audioCategory = (.playAndRecord, [.allowBluetoothHFP, .duckOthers])
    }

    init(fixture state: VoiceAttributes.ContentState) {
        let levels = (0..<Dictation.levelCount).map { 0.25 + 0.6 * abs(sin(Double($0) * 0.7)) * Double($0 % 5 + 1) / 5 }
        let startedAt = Date.now.addingTimeInterval(-7)
        dictation = Dictation(fixture: levels, startedAt: startedAt)
        attributes = VoiceAttributes(bot: VoiceBot(name: "default", title: "Hermes", session: nil, lastActive: nil, shape: "blob", color: "#8b5cf6", expression: "happy", hidden: false), startedAt: startedAt)
        self.state = state
    }

    func toggle(_ name: String?) async -> VoiceStart {
        voiceLog.notice("toggle, recording: \(self.recording != nil, privacy: .public)")
        if recording != nil {
            await send()
            return .started
        }
        guard dictation.phase == .idle else {
            voiceLog.notice("still transcribing, press ignored")
            return .started
        }
        await cancel()
        guard let (stored, urlSession) = restoredURLSession() else {
            voiceLog.notice("no stored session")
            return .needsCrew(String(localized: "Sign in to Crew first."))
        }
        guard let bot = VoiceBot.choose(name, from: VoiceBot.cached()) else {
            voiceLog.notice("no cached bots")
            return .needsCrew(String(localized: "Open Crew to load your bots."))
        }
        guard AVAudioApplication.shared.recordPermission != .undetermined else {
            voiceLog.notice("microphone permission not asked yet")
            return .needsPermission
        }
        voiceLog.notice("requesting Live Activity, enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled, privacy: .public)")
        let id: Activity<VoiceAttributes>.ID
        let started = VoiceAttributes(bot: bot, startedAt: .now)
        do {
            id = try Activity.request(attributes: started, content: ActivityContent(state: .init(phase: .recording), staleDate: nil)).id
        } catch {
            voiceLog.error("Live Activity request failed: \(error, privacy: .public)")
            return .failed(error.localizedDescription)
        }
        activity = id
        attributes = started
        state = .init(phase: .recording)
        voiceLog.notice("Live Activity started, starting audio")
        await dictation.start { audio in
            voiceLog.notice("transcribing \(audio.count, privacy: .public) bytes on the server")
            var request = hermesRequest("api/audio/transcribe", on: stored.server, json: ["data_url": "data:audio/m4a;base64,\(audio.base64EncodedString())", "mime_type": "audio/m4a"])
            request.url?.append(queryItems: [URLQueryItem(name: "profile", value: bot.name)])
            request.timeoutInterval = 60
            return try await fetch(request, with: urlSession, as: Transcription.self).transcript
        }
        voiceLog.notice("audio started, on device: \(self.dictation.isOnDevice, privacy: .public), failure: \(self.dictation.failure ?? "none", privacy: .public)")
        if let failure = dictation.failure {
            await show(.init(phase: .failed, failure: failure), on: id)
            return .started
        }
        recording = (bot, stored.server, urlSession)
        return .started
    }

    func showFailure(_ message: String, for name: String?) {
        guard activity == nil, let bot = VoiceBot.choose(name, from: VoiceBot.cached()) else { return }
        let failed = VoiceAttributes(bot: bot, startedAt: .now)
        do {
            activity = try Activity.request(attributes: failed, content: ActivityContent(state: .init(phase: .failed, failure: message), staleDate: nil)).id
            attributes = failed
            state = .init(phase: .failed, failure: message)
        } catch {
            voiceLog.error("Live Activity request failed: \(error, privacy: .public)")
        }
    }

    func send() async {
        guard let (bot, server, urlSession) = recording, let id = activity else { return }
        recording = nil
        voiceLog.notice("recording done, transcribing")
        await show(.init(phase: .sending), on: id)
        await dictation.stop()
        let text = dictation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceLog.notice("transcribed \(text.count, privacy: .public) characters, failure: \(self.dictation.failure ?? "none", privacy: .public)")
        if let failure = dictation.failure {
            return await show(.init(phase: .failed, failure: failure), on: id)
        }
        guard !text.isEmpty else {
            return await finish(id, showing: .init(phase: .failed, failure: String(localized: "Crew didn't hear anything.")))
        }
        let draft = ChatDrafts.shared.texts[bot.name, default: ""]
        ChatDrafts.shared.update(bot.name, to: [draft, text].filter { !$0.isEmpty }.joined(separator: "\n"))
        guard await submit(text, to: bot, on: server, with: urlSession) else {
            return await show(.init(phase: .failed, failure: String(localized: "Couldn't send. It's saved as a draft.")), on: id)
        }
        ChatDrafts.shared.update(bot.name, to: draft)
        await finish(id, showing: .init(phase: .sent))
    }

    func cancel() async {
        recording = nil
        await dictation.cancel()
        guard let id = activity else { return }
        voiceLog.notice("Live Activity dismissed")
        activity = nil
        await end(id, showing: .init(phase: .recording), dismissal: .immediate)
    }

    private func finish(_ id: Activity<VoiceAttributes>.ID, showing state: VoiceAttributes.ContentState) async {
        await show(state, on: id)
        try? await Task.sleep(for: .seconds(3))
        guard activity == id else { return }
        activity = nil
        await end(id, showing: state, dismissal: .immediate)
    }

    private func submit(_ text: String, to bot: VoiceBot, on server: URL, with urlSession: URLSession) async -> Bool {
        guard let gateway = await connectedGateway(to: server, with: urlSession) else {
            voiceLog.error("gateway did not connect")
            return false
        }
        let sent: Bool
        do {
            let (_, snapshot) = try await openBotChat(bot.session.map(StoredSessionID.init(rawValue:)), profile: bot.name, via: gateway)
            _ = try await gateway.call("prompt.submit", ["session_id": snapshot.sessionID.rawValue, "text": text], as: JSONValue.self)
            voiceLog.notice("prompt submitted")
            sent = true
        } catch {
            voiceLog.error("send failed: \(error, privacy: .public)")
            sent = false
        }
        await gateway.disconnect()
        return sent
    }

    nonisolated private func show(_ state: VoiceAttributes.ContentState, on id: Activity<VoiceAttributes>.ID) async {
        await MainActor.run { self.state = state }
        await Activity<VoiceAttributes>.activities.first { $0.id == id }?.update(ActivityContent(state: state, staleDate: nil))
    }

    nonisolated private func end(_ id: Activity<VoiceAttributes>.ID, showing state: VoiceAttributes.ContentState, dismissal: ActivityUIDismissalPolicy) async {
        await MainActor.run { attributes = nil }
        await Activity<VoiceAttributes>.activities.first { $0.id == id }?.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: dismissal)
    }
}

struct CrewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TalkToBotIntent(), phrases: ["Talk to a bot in \(.applicationName)"], shortTitle: "Talk to Bot", systemImageName: "waveform")
    }
}
#endif
