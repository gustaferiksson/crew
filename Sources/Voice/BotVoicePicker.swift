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
                    speaker.speak(String(localized: "Hi, I'm \(bot.title). This is how I sound."), id: sampleID, profile: bot.name, from: bot.title)
                }
            }
            Toggle("Read Replies Aloud", isOn: Binding(get: { voices.readingAloud.contains(bot.name) }, set: { voices.readAloud($0, for: bot.name) }))
                .toggleStyle(.switch)
        } header: {
            Text("Voice")
        } footer: {
            Text("New replies are read aloud while this chat is open. Saved on this device. Download more voices in Accessibility settings.")
        }
    }
}
