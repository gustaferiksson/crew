import AVFoundation
import MediaPlayer
import Observation
#if os(iOS)
import CallKit

private let calls = CXCallObserver()
#endif

func isCallInProgress() -> Bool {
    #if os(iOS)
    calls.calls.contains { !$0.hasEnded }
    #else
    false
    #endif
}

@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    let voices: BotVoices
    private(set) var speakingID: String?
    private(set) var isPaused = false
    var isRecording = false
    @ObservationIgnored private(set) var utterance: AVSpeechUtterance?
    @ObservationIgnored private let synthesizer: AVSpeechSynthesizer
    @ObservationIgnored private let nowPlaying: MPNowPlayingInfoCenter?
    @ObservationIgnored private let isOnCall: @MainActor () -> Bool
    @ObservationIgnored private var title = ""
    @ObservationIgnored private var interruptions: Task<Void, Never>?
    @ObservationIgnored private var routeChanges: Task<Void, Never>?

    init(voices: BotVoices = BotVoices(), synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(), nowPlaying: MPNowPlayingInfoCenter? = .default(), isOnCall: @escaping @MainActor () -> Bool = isCallInProgress) {
        self.voices = voices
        self.synthesizer = synthesizer
        self.nowPlaying = nowPlaying
        self.isOnCall = isOnCall
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        interruptions = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                self?.stop()
            }
        }
        routeChanges = Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification)
            where note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                self?.pause()
            }
        }
        #endif
    }

    func readAloud(_ turn: Turn, profile: String, from name: String) {
        guard turn.status == .complete, voices.readingAloud.contains(profile), !isOnCall() else { return }
        speak(BotAnswer.speech(from: turn.reply), id: "\(turn.id)-reply", profile: profile, from: name)
    }

    func speak(_ text: String, id: String, profile: String?, from name: String) {
        guard !isRecording, !text.isEmpty else { return }
        halt()
        let next = AVSpeechUtterance(string: text)
        next.voice = voices.voice(for: profile, speaking: text)
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        #endif
        utterance = next
        speakingID = id
        title = name
        synthesizer.speak(next)
        listenToRemoteCommands()
        publish(rate: 1)
    }

    func pause() {
        guard utterance != nil, !isPaused, synthesizer.pauseSpeaking(at: .word) else { return }
        isPaused = true
        publish(rate: 0)
    }

    func resume() {
        guard isPaused, synthesizer.continueSpeaking() else { return }
        isPaused = false
        publish(rate: 1)
    }

    func stop() {
        guard utterance != nil else { return }
        halt()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    func finished(_ finished: AVSpeechUtterance) {
        guard utterance === finished else { return }
        stop()
    }

    private func halt() {
        utterance = nil
        speakingID = nil
        isPaused = false
        synthesizer.stopSpeaking(at: .immediate)
        guard let nowPlaying else { return }
        nowPlaying.nowPlayingInfo = nil
        nowPlaying.playbackState = .stopped
        let commands = MPRemoteCommandCenter.shared()
        for command in [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand, commands.stopCommand] {
            command.removeTarget(nil)
        }
    }

    private func publish(rate: Double) {
        guard let nowPlaying, let utterance else { return }
        nowPlaying.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: String(utterance.speechString.prefix { $0 != "\n" }.prefix(120)),
            MPNowPlayingInfoPropertyPlaybackRate: rate,
        ]
        nowPlaying.playbackState = rate > 0 ? .playing : .paused
    }

    private func listenToRemoteCommands() {
        guard nowPlaying != nil else { return }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPaused { self.resume() } else { self.pause() }
            }
            return .success
        }
        commands.stopCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let finished = utterance
        Task { @MainActor in self.finished(finished) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let finished = utterance
        Task { @MainActor in self.finished(finished) }
    }
}
