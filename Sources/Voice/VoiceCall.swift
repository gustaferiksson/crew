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

@MainActor
final class VoiceCall: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceCall()

    private let dictation = Dictation()
    private let output = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()
    private var activity: Activity<VoiceAttributes>.ID?
    private var conversation: Task<Void, Never>?
    private var spoken: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        dictation.audioCategory = (.playAndRecord, [.defaultToSpeaker, .allowBluetoothHFP])
        output.attach(player)
        synthesizer.delegate = self
    }

    func toggle(_ name: String?) async -> VoiceStart {
        guard activity == nil else {
            await end()
            return .started
        }
        guard let (stored, urlSession) = restoredURLSession() else { return .needsCrew(String(localized: "Sign in to Crew first.")) }
        guard let bot = VoiceBot.choose(name, from: VoiceBot.cached()) else { return .needsCrew(String(localized: "Open Crew to load your bots.")) }
        guard AVAudioApplication.shared.recordPermission != .undetermined else { return .needsPermission }
        let id: Activity<VoiceAttributes>.ID
        do {
            id = try Activity.request(attributes: VoiceAttributes(bot: bot, startedAt: .now), content: ActivityContent(state: .init(phase: .connecting), staleDate: nil)).id
        } catch {
            return .failed(error.localizedDescription)
        }
        activity = id
        await dictation.start { _ in throw VoiceFailure(errorDescription: nil) }
        if let failure = dictation.failure {
            await fail(failure)
            return .started
        }
        guard dictation.isOnDevice else {
            await dictation.cancel()
            await fail(String(localized: "Calls need on-device speech recognition for your language."))
            return .started
        }
        dictation.isPaused = true
        conversation = Task { await converse(with: bot, on: stored.server, using: urlSession) }
        return .started
    }

    func end() async {
        guard let id = activity else { return }
        activity = nil
        conversation?.cancel()
        conversation = nil
        stopSpeaking()
        await dictation.cancel()
        await show(.init(phase: .connecting), on: id, ending: .immediate)
    }

    private func converse(with bot: VoiceBot, on server: URL, using urlSession: URLSession) async {
        guard let gateway = await connectedGateway(to: server, with: urlSession) else {
            return await fail(String(localized: "Couldn't reach the server."))
        }
        var said = ""
        do {
            let (_, snapshot) = try await openBotChat(bot.session.map(StoredSessionID.init(rawValue:)), profile: bot.name, via: gateway)
            var heard = dictation.settledText.count
            while !Task.isCancelled {
                dictation.isPaused = false
                await show(.init(phase: .listening))
                said = try await nextUtterance(after: heard)
                heard = dictation.settledText.count
                dictation.isPaused = true
                await show(.init(phase: .thinking))
                let reply = try await VoiceTurn.reply(to: said, in: snapshot.sessionID, via: gateway)
                said = ""
                await show(.init(phase: .speaking))
                await speak(reply, as: bot.name, on: server, using: urlSession)
                heard = dictation.settledText.count
            }
        } catch let error where Task.isCancelled || error is CancellationError {
        } catch let failure as VoiceFailure {
            await fail(failure.errorDescription ?? "")
        } catch {
            guard !said.isEmpty else { return await fail(error.localizedDescription) }
            let draft = ChatDrafts.shared.texts[bot.name, default: ""]
            ChatDrafts.shared.update(bot.name, to: [draft, said].filter { !$0.isEmpty }.joined(separator: "\n"))
            await fail(String(localized: "Couldn't send. It's saved as a draft."))
        }
        await gateway.disconnect()
    }

    private func nextUtterance(after heard: Int) async throws -> String {
        let changes = Observations { [dictation] in (dictation.text, dictation.settledText, dictation.levels, dictation.failure) }
        for await (text, settled, levels, failure) in changes {
            if let failure { throw VoiceFailure(errorDescription: failure) }
            if let said = VoiceTurn.utterance(text: text, settled: settled, heard: heard, levels: levels) { return said }
        }
        throw CancellationError()
    }

    private func speak(_ reply: String, as profile: String, on server: URL, using urlSession: URLSession) async {
        let plain = (try? AttributedString(markdown: reply)).map { String($0.characters) } ?? reply
        guard !plain.isEmpty, !Task.isCancelled else { return }
        let url = URL.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let audio = try? await VoiceTurn.audio(speaking: plain, profile: profile, on: server, with: urlSession),
              (try? audio.write(to: url)) != nil,
              let file = try? AVAudioFile(forReading: url) else {
            return await speakOnDevice(plain)
        }
        do {
            try output.connectNode(player, to: output.mainMixerNode, format: file.processingFormat)
            try output.start()
            try player.playAudio()
        } catch {
            return await speakOnDevice(plain)
        }
        _ = await player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack)
        player.stop()
        output.stop()
    }

    private func speakOnDevice(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }.max { $0.quality.rawValue < $1.quality.rawValue }
        await withCheckedContinuation { continuation in
            spoken = continuation
            synthesizer.speak(utterance)
        }
    }

    private func stopSpeaking() {
        player.stop()
        output.stop()
        synthesizer.stopSpeaking(at: .immediate)
        spoken?.resume()
        spoken = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            spoken?.resume()
            spoken = nil
        }
    }

    private func fail(_ message: String) async {
        stopSpeaking()
        await dictation.cancel()
        await show(.init(phase: .failed, failure: message))
    }

    private func show(_ state: VoiceAttributes.ContentState) async {
        guard let activity else { return }
        await show(state, on: activity, ending: nil)
    }

    nonisolated private func show(_ state: VoiceAttributes.ContentState, on id: Activity<VoiceAttributes>.ID, ending dismissal: ActivityUIDismissalPolicy?) async {
        guard let activity = Activity<VoiceAttributes>.activities.first(where: { $0.id == id }) else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        guard let dismissal else { return await activity.update(content) }
        await activity.end(content, dismissalPolicy: dismissal)
    }
}

struct CrewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TalkToBotIntent(), phrases: ["Talk to a bot in \(.applicationName)"], shortTitle: "Talk to Bot", systemImageName: "phone.fill")
    }
}
#endif
