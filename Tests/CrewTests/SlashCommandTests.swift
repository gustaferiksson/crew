import Foundation
import Testing

private func recordedCatalog() throws -> [SlashCommand] {
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/commands.catalog.v0.22.5.json")
    return try JSONDecoder().decode(SlashCatalog.self, from: Data(contentsOf: file)).commands
}

@Test func slashCatalogListsBuiltInsAndSkillsWithTheirSummaries() throws {
    let commands = try recordedCatalog()
    #expect(commands.first == SlashCommand(name: "/new", summary: "Start a new session (fresh session ID + history) (usage: /new [name])"))
    #expect(commands.contains { $0.name == "/compress" })
    #expect(commands.contains(SlashCommand(name: "/crew-ui", summary: "Use for checklists, tables, charts, maps, forms, carousels.")))
    #expect(commands.count == 121)
}

@Test func slashCatalogDropsCommandsDesktopHandlesElsewhere() throws {
    let names = Set(try recordedCatalog().map(\.name))
    #expect(names.isDisjoint(with: ["/clear", "/copy", "/paste", "/redraw", "/quit", "/model", "/voice", "/login", "/fast", "/mouse", "/compact"]))
}

@Test func slashPickerFiltersByPrefixIgnoringCase() throws {
    let commands = try recordedCatalog()
    let matches = SlashPicker(query: "RE", commands: commands) { _ in }.matches.map(\.name)
    #expect(matches == ["/retry", "/refine", "/review", "/resume", "/reasoning", "/requesting-code-review"])
    #expect(SlashPicker(query: "", commands: commands) { _ in }.matches.count == commands.count)
    #expect(SlashPicker(query: "zzz", commands: commands) { _ in }.matches.isEmpty)
}
