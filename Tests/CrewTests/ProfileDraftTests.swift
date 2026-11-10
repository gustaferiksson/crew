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

@Test func browsingNeedsBrowserAndTerminal() throws {
    let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
    let roster = try JSONDecoder().decode(ProfileRoster.self, from: Data(contentsOf: fixtures.appending(path: "profiles.list.v0.21.7.json")))
    let bot = try #require(roster.profiles.first)
    let loaded = try JSONDecoder().decode([ProfileCapability].self, from: Data(contentsOf: fixtures.appending(path: "tools.toolsets.v0.21.7.json")))
    let details = ProfileDetails(name: bot.name, description: "", soul: "", model: nil, skills: [], mcpServers: [])
    let turningOff = { (name: String) in
        ProfileDraft(bot: bot, details: details, toolsets: loaded.map { toolset in
            var toolset = toolset
            if toolset.name == name { toolset.enabled = false }
            return toolset
        }).canBrowse
    }

    #expect(ProfileDraft(bot: bot).canBrowse == nil)
    #expect(ProfileDraft(bot: bot, details: details, toolsets: loaded).canBrowse == true)
    #expect(turningOff("browser") == false)
    #expect(turningOff("terminal") == false)
}
