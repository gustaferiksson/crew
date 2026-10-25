import Foundation
import Testing

private let quiet = Array(repeating: 0.1, count: VoiceTurn.quietSpan)
private let speaking = quiet.dropLast() + [0.7]

@Test func aSettledPhraseFollowedByQuietIsAnUtterance() {
    #expect(VoiceTurn.utterance(text: "What's on today?", settled: "What's on today?", heard: 0, levels: speaking + quiet) == "What's on today?")
}

@Test func onlyTheWordsSinceTheLastTurnAreSent() {
    #expect(VoiceTurn.utterance(text: "Hello. Any mail?", settled: "Hello. Any mail?", heard: 6, levels: quiet) == "Any mail?")
}

@Test func theCallWaitsWhileSpeechIsStillVolatile() {
    #expect(VoiceTurn.utterance(text: "Remind me to", settled: "", heard: 0, levels: quiet) == nil)
    #expect(VoiceTurn.utterance(text: "Remind me to call", settled: "Remind me to", heard: 0, levels: quiet) == nil)
}

@Test func theCallWaitsUntilTheSpeakerFallsQuiet() {
    #expect(VoiceTurn.utterance(text: "Book a table", settled: "Book a table", heard: 0, levels: Array(speaking)) == nil)
    #expect(VoiceTurn.utterance(text: "Book a table", settled: "Book a table", heard: 0, levels: Array(quiet.prefix(4))) == nil)
}

@Test func nothingNewOrOnlyWhitespaceIsNoUtterance() {
    #expect(VoiceTurn.utterance(text: "Hello.", settled: "Hello.", heard: 6, levels: quiet) == nil)
    #expect(VoiceTurn.utterance(text: "Hello.  ", settled: "Hello.  ", heard: 6, levels: quiet) == nil)
}
