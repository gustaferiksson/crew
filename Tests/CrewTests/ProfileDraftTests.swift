import Foundation
import Testing

@Test func titlelessBotPrefillsShownName() throws {
    let rosterFile = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/profiles.list.v0.21.7.json")
    let roster = try JSONDecoder().decode(ProfileRoster.self, from: Data(contentsOf: rosterFile))
    let bot = try #require(roster.profiles.first { $0.meta.title == nil })
    let draft = ProfileDraft(bot: bot)
    #expect(draft.fields.identity.title == bot.title)
    #expect(!draft.isDirty)
}
