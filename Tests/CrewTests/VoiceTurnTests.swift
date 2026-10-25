import Foundation
import Testing

private let quiet = Array(repeating: 0.1, count: VoiceTurn.quietSpan)
private let speaking = quiet.dropLast() + [0.7]

@Test func aSettledPhraseFollowedByQuietIsSaid() {
    #expect(VoiceTurn.listen(text: "What's on today?", settled: "What's on today?", heard: 0, levels: speaking + quiet) == .said("What's on today?"))
}

@Test func onlyTheWordsSinceTheLastTurnAreSaid() {
    #expect(VoiceTurn.listen(text: "Hello. Any mail?", settled: "Hello. Any mail?", heard: 6, levels: quiet) == .said("Any mail?"))
}

@Test func quietWithVolatileWordsAsksToSettle() {
    #expect(VoiceTurn.listen(text: "Remind me to", settled: "", heard: 0, levels: quiet) == .settling)
    #expect(VoiceTurn.listen(text: "Remind me to call", settled: "Remind me to", heard: 0, levels: quiet) == .settling)
}

@Test func theCallKeepsListeningUntilTheSpeakerFallsQuiet() {
    #expect(VoiceTurn.listen(text: "Book a table", settled: "Book a table", heard: 0, levels: Array(speaking)) == .speaking)
    #expect(VoiceTurn.listen(text: "Book a table", settled: "Book a table", heard: 0, levels: Array(quiet.prefix(4))) == .speaking)
}

@Test func nothingNewOrOnlyWhitespaceKeepsListening() {
    #expect(VoiceTurn.listen(text: "Hello.", settled: "Hello.", heard: 6, levels: quiet) == .speaking)
    #expect(VoiceTurn.listen(text: "Hello.  ", settled: "Hello.  ", heard: 6, levels: quiet) == .speaking)
}
