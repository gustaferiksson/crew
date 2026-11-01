import AVFoundation
import Foundation
import Testing

nonisolated private final class SilentSynthesizer: AVSpeechSynthesizer {
    private(set) var spoken: [String] = []

    override func speak(_ utterance: AVSpeechUtterance) {
        spoken.append(utterance.speechString)
    }

    override func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        true
    }

    override func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        true
    }

    override func continueSpeaking() -> Bool {
        true
    }
}

private let installed = [
    VoiceOption(id: "compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: 1),
    VoiceOption(id: "super-compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: 1),
    VoiceOption(id: "eloquence.en-GB.Eddy", name: "Eddy", language: "en-GB", quality: 1),
    VoiceOption(id: "compact.en-GB.Daniel", name: "Daniel", language: "en-GB", quality: 1),
    VoiceOption(id: "enhanced.en-GB.Serena", name: "Serena", language: "en-GB", quality: 2),
    VoiceOption(id: "premium.en-US.Ava", name: "Ava", language: "en-US", quality: 3),
    VoiceOption(id: "compact.sv-SE.Alva", name: "Alva", language: "sv-SE", quality: 1),
    VoiceOption(id: "compact.fr-FR.Thomas", name: "Thomas", language: "fr-FR", quality: 1),
]

@Test func pickerListsPreferredLanguagesBestQualityFirst() {
    let sections = voiceSections(of: installed, languages: ["en", "sv"])
    #expect(sections.map(\.language) == ["en-US", "en-GB", "sv-SE"])
    #expect(sections[0].voices.map(\.title) == ["Ava (Premium)", "Samantha"])
    #expect(sections[1].voices.map(\.title) == ["Serena (Enhanced)", "Daniel", "Eddy"])
}

@Test func storedVoiceWinsWhileInstalledElseBestForTheLanguage() {
    #expect(resolvedVoice(stored: "compact.en-GB.Daniel", language: "en", region: "en-US", in: installed)?.id == "compact.en-GB.Daniel")
    #expect(resolvedVoice(stored: "deleted.en-US.Zoe", language: "en", region: "en-US", in: installed)?.id == "premium.en-US.Ava")
    #expect(resolvedVoice(stored: nil, language: "sv", region: "en-US", in: installed)?.id == "compact.sv-SE.Alva")
    #expect(resolvedVoice(stored: nil, language: "ja", region: "en-GB", in: installed)?.id == "premium.en-US.Ava")
    #expect(resolvedVoice(stored: nil, language: nil, region: "fr-FR", in: installed)?.id == "compact.fr-FR.Thomas")
    #expect(resolvedVoice(stored: nil, language: "ja", region: "ja-JP", in: installed) == nil)
}

@Test func choicesAreKeptPerBotOnThisDevice() throws {
    let suite = "crew-tests-bot-voices"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    BotVoices(defaults: defaults).choose("premium.en-US.Ava", for: "ada")
    let reopened = BotVoices(defaults: defaults)
    #expect(reopened.chosen == ["ada": "premium.en-US.Ava"])
    reopened.choose(nil, for: "ada")
    #expect(BotVoices(defaults: defaults).chosen.isEmpty)
}

@Test func speakingAnotherReplyReplacesTheFirst() throws {
    let synthesizer = SilentSynthesizer()
    let speaker = Speaker(voices: BotVoices(defaults: try #require(UserDefaults(suiteName: "crew-tests-speaker"))), synthesizer: synthesizer, nowPlaying: nil)
    speaker.speak("First reply.", id: "t1", profile: "ada", from: "Ada")
    let first = try #require(speaker.utterance)
    speaker.speak("Second reply.", id: "t2", profile: "ada", from: "Ada")
    #expect(speaker.speakingID == "t2")
    speaker.finished(first)
    #expect(speaker.speakingID == "t2")
    let second = try #require(speaker.utterance)
    speaker.finished(second)
    #expect(speaker.speakingID == nil)
    speaker.speak("Third reply.", id: "t3", profile: nil, from: "Ada")
    speaker.stop()
    #expect(speaker.speakingID == nil)
    #expect(synthesizer.spoken == ["First reply.", "Second reply.", "Third reply."])
}

@Test func emptySpeechSpeaksNothing() throws {
    let synthesizer = SilentSynthesizer()
    let speaker = Speaker(voices: BotVoices(defaults: try #require(UserDefaults(suiteName: "crew-tests-speaker"))), synthesizer: synthesizer, nowPlaying: nil)
    speaker.speak(BotAnswer.speech(from: "```swift\nlet a = 1\n```"), id: "t1", profile: "ada", from: "Ada")
    #expect(speaker.speakingID == nil)
    #expect(synthesizer.spoken.isEmpty)
}

@Test func nothingSpeaksWhileTheMicrophoneRecords() throws {
    let synthesizer = SilentSynthesizer()
    let speaker = Speaker(voices: BotVoices(defaults: try #require(UserDefaults(suiteName: "crew-tests-speaker"))), synthesizer: synthesizer, nowPlaying: nil)
    speaker.isRecording = true
    speaker.speak("A reply.", id: "t1", profile: "ada", from: "Ada")
    #expect(speaker.speakingID == nil)
    #expect(synthesizer.spoken.isEmpty)
}

@Test func autoReadSpeaksOnlyFinishedRepliesOfBotsThatReadAloud() throws {
    let suite = "crew-tests-read-aloud"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let synthesizer = SilentSynthesizer()
    let voices = BotVoices(defaults: defaults)
    let speaker = Speaker(voices: voices, synthesizer: synthesizer, nowPlaying: nil, isOnCall: { false })
    let reply = Turn(id: "t1", reply: "**Done.** Here it is.", status: .complete, startedAt: .now)
    speaker.readAloud(reply, profile: "ada", from: "Ada")
    #expect(synthesizer.spoken.isEmpty)
    voices.readAloud(true, for: "ada")
    #expect(BotVoices(defaults: defaults).readingAloud == ["ada"])
    var interrupted = reply
    interrupted.status = .interrupted
    speaker.readAloud(interrupted, profile: "ada", from: "Ada")
    speaker.isRecording = true
    speaker.readAloud(reply, profile: "ada", from: "Ada")
    speaker.isRecording = false
    Speaker(voices: voices, synthesizer: synthesizer, nowPlaying: nil, isOnCall: { true }).readAloud(reply, profile: "ada", from: "Ada")
    #expect(synthesizer.spoken.isEmpty)
    speaker.readAloud(reply, profile: "ada", from: "Ada")
    #expect(synthesizer.spoken == ["Done. Here it is."])
    #expect(speaker.speakingID == "t1-reply")
    voices.readAloud(false, for: "ada")
    #expect(BotVoices(defaults: defaults).readingAloud.isEmpty)
}

@Test func lockScreenPauseAndPlayResumeTheSameReply() throws {
    let speaker = Speaker(voices: BotVoices(defaults: try #require(UserDefaults(suiteName: "crew-tests-speaker"))), synthesizer: SilentSynthesizer(), nowPlaying: nil)
    speaker.pause()
    #expect(!speaker.isPaused)
    speaker.speak("A long reply.", id: "t1", profile: "ada", from: "Ada")
    speaker.pause()
    #expect(speaker.isPaused)
    #expect(speaker.speakingID == "t1")
    speaker.resume()
    #expect(!speaker.isPaused)
    speaker.pause()
    speaker.stop()
    #expect(!speaker.isPaused)
    #expect(speaker.speakingID == nil)
}
