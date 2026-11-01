import AVFoundation
import Observation

@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    let voices: BotVoices
    private(set) var speakingID: String?
    var isRecording = false
    @ObservationIgnored private(set) var utterance: AVSpeechUtterance?
    @ObservationIgnored private let synthesizer: AVSpeechSynthesizer
    @ObservationIgnored private var interruptions: Task<Void, Never>?

    init(voices: BotVoices = BotVoices(), synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()) {
        self.voices = voices
        self.synthesizer = synthesizer
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        interruptions = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                self?.stop()
            }
        }
        #endif
    }

    func speak(_ text: String, id: String, profile: String?) {
        guard !isRecording else { return }
        halt()
        guard !text.isEmpty else { return }
        let next = AVSpeechUtterance(string: text)
        next.voice = voices.voice(for: profile, speaking: text)
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        #endif
        utterance = next
        speakingID = id
        synthesizer.speak(next)
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
        synthesizer.stopSpeaking(at: .immediate)
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
