import SwiftUI

struct BotVoicePicker: View {
    let bot: Bot

    private let speaker = Speaker.shared

    var body: some View {
        let voices = speaker.voices
        let sampleID = "sample-\(bot.name)"
        Section {
            Picker("Voice", selection: Binding(get: { voices.selection(for: bot.name) }, set: { voice in
                if speaker.speakingID == sampleID { speaker.stop() }
                voices.choose(voice, for: bot.name)
            })) {
                Text("Automatic").tag(String?.none)
                ForEach(voices.sections) { section in
                    Section(Locale.current.localizedString(forIdentifier: section.language) ?? section.language) {
                        ForEach(section.voices) { voice in
                            Text(voice.title).tag(Optional(voice.id))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            if speaker.speakingID == sampleID {
                Button("Stop", systemImage: "stop.fill") { speaker.stop() }
            } else {
                Button("Play Sample", systemImage: "play.fill") {
                    speaker.speak(String(localized: "Hi, I'm \(bot.title). This is how I sound."), id: sampleID, profile: bot.name)
                }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Saved on this device. Download more voices in Accessibility settings.")
        }
    }
}
