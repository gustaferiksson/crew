import Foundation
import Testing

private func bot(_ name: String, active: TimeInterval?, hidden: Bool = false) -> VoiceBot {
    VoiceBot(name: name, title: name.capitalized, session: nil, lastActive: active.map(Date.init(timeIntervalSince1970:)), shape: "blob", color: "#8b5cf6", expression: nil, hidden: hidden)
}

@Test func theControlsBotWinsEvenWhenHidden() {
    let bots = [bot("vera", active: 300), bot("scout", active: 100, hidden: true)]
    #expect(VoiceBot.choose("scout", from: bots)?.name == "scout")
}

@Test func withoutAChoiceTheMostRecentListedBotIsUsed() {
    let bots = [bot("scout", active: 100), bot("ghost", active: 900, hidden: true), bot("vera", active: 300), bot("new", active: nil)]
    #expect(VoiceBot.choose(nil, from: bots)?.name == "vera")
}

@Test func aDeletedChoiceFallsBackToTheMostRecentBot() {
    #expect(VoiceBot.choose("gone", from: [bot("scout", active: 100), bot("vera", active: 300)])?.name == "vera")
}

@Test func noListedBotsMeansNoTarget() {
    #expect(VoiceBot.choose(nil, from: [bot("ghost", active: 900, hidden: true)]) == nil)
    #expect(VoiceBot.choose(nil, from: []) == nil)
}
