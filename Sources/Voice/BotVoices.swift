import AVFoundation
import NaturalLanguage
import Observation

nonisolated struct VoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let quality: Int

    var title: String {
        if quality >= AVSpeechSynthesisVoiceQuality.premium.rawValue { return String(localized: "\(name) (Premium)") }
        if quality == AVSpeechSynthesisVoiceQuality.enhanced.rawValue { return String(localized: "\(name) (Enhanced)") }
        return name
    }

    var baseLanguage: String {
        String(language.prefix { $0 != "-" })
    }
}

nonisolated struct VoiceSection: Identifiable, Sendable {
    let language: String
    let voices: [VoiceOption]

    var id: String { language }
}

nonisolated func voiceSections(of voices: [VoiceOption], languages: [String]) -> [VoiceSection] {
    let wanted = voices.filter { languages.contains($0.baseLanguage) }.map { ("\($0.language) \($0.name)", $0) }
    let unique = Dictionary(wanted) { $0.quality >= $1.quality ? $0 : $1 }.values
    let order = { (section: VoiceSection) in (languages.firstIndex(of: section.voices[0].baseLanguage) ?? 0, -section.voices[0].quality, section.language) }
    return Dictionary(grouping: unique, by: \.language)
        .map { VoiceSection(language: $0.key, voices: $0.value.sorted { ($1.quality, $0.name) < ($0.quality, $1.name) }) }
        .sorted { order($0) < order($1) }
}

nonisolated func resolvedVoice(stored: String?, language: String?, region: String, in voices: [VoiceOption]) -> VoiceOption? {
    if let stored, let voice = voices.first(where: { $0.id == stored }) { return voice }
    let fallback = String(region.prefix { $0 != "-" })
    for base in [language, fallback].compactMap(\.self) {
        let best = voices.filter { $0.baseLanguage == base }.max { ($0.quality, $0.language == region ? 1 : 0) < ($1.quality, $1.language == region ? 1 : 0) }
        if let best { return best }
    }
    return nil
}

@Observable
final class BotVoices {
    private(set) var installed: [VoiceOption] = []
    private(set) var chosen: [String: String]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var changes: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chosen = defaults.dictionary(forKey: "botVoices") as? [String: String] ?? [:]
        reload()
        changes = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVSpeechSynthesizer.availableVoicesDidChangeNotification) {
                self?.reload()
            }
        }
    }

    var sections: [VoiceSection] {
        voiceSections(of: installed, languages: Locale.preferredLanguages.map { Locale.Language(identifier: $0).languageCode?.identifier ?? $0 })
    }

    func selection(for profile: String) -> String? {
        chosen[profile].flatMap { id in installed.contains { $0.id == id } ? id : nil }
    }

    func choose(_ voice: String?, for profile: String) {
        chosen[profile] = voice
        defaults.set(chosen, forKey: "botVoices")
    }

    func voice(for profile: String?, speaking text: String) -> AVSpeechSynthesisVoice? {
        let language = NLLanguageRecognizer.dominantLanguage(for: text).flatMap { Locale.Language(identifier: $0.rawValue).languageCode?.identifier }
        let option = resolvedVoice(stored: profile.flatMap { chosen[$0] }, language: language, region: AVSpeechSynthesisVoice.currentLanguageCode(), in: installed)
        return option.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) }
    }

    private func reload() {
        installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .map { VoiceOption(id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality.rawValue) }
    }
}
