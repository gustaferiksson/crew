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
    let speaker = Speaker(voices: BotVoices(defaults: try #require(UserDefaults(suiteName: "crew-tests-speaker"))), synthesizer: synthesizer)
    speaker.speak("First reply.", id: "t1", profile: "ada")
    let first = try #require(speaker.utterance)
    speaker.speak("Second reply.", id: "t2", profile: "ada")
    #expect(speaker.speakingID == "t2")
    speaker.finished(first)
    #expect(speaker.speakingID == "t2")
    let second = try #require(speaker.utterance)
    speaker.finished(second)
    #expect(speaker.speakingID == nil)
    speaker.speak("Third reply.", id: "t3", profile: nil)
    speaker.stop()
    #expect(speaker.speakingID == nil)
    #expect(synthesizer.spoken == ["First reply.", "Second reply.", "Third reply."])
}

@Test func emptySpeechSpeaksNothing() throws {
    let synthesizer = SilentSynthesizer()
    let speaker = Speaker(voices: BotVoices(defaults: try #require(UserDefaults(suiteName: "crew-tests-speaker"))), synthesizer: synthesizer)
    speaker.speak(speechText(from: "```swift\nlet a = 1\n```"), id: "t1", profile: "ada")
    #expect(speaker.speakingID == nil)
    #expect(synthesizer.spoken.isEmpty)
}

@Test func nothingSpeaksWhileTheMicrophoneRecords() throws {
    let synthesizer = SilentSynthesizer()
    let speaker = Speaker(voices: BotVoices(defaults: try #require(UserDefaults(suiteName: "crew-tests-speaker"))), synthesizer: synthesizer)
    speaker.isRecording = true
    speaker.speak("A reply.", id: "t1", profile: "ada")
    #expect(speaker.speakingID == nil)
    #expect(synthesizer.spoken.isEmpty)
}
