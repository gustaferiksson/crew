import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private func recordedCatalog() throws -> [SlashCommand] {
    try JSONDecoder().decode(SlashCatalog.self, from: Data(contentsOf: fixtures.appending(path: "commands.catalog.v0.22.5.json"))).commands
}

private func recordedReplies() throws -> [String: SlashReply] {
    try JSONDecoder().decode([String: SlashReply].self, from: Data(contentsOf: fixtures.appending(path: "slash.exec.v0.22.5.json")))
}

@Test func slashCatalogListsBuiltInsAndSkillsWithTheirSummaries() throws {
    let commands = try recordedCatalog()
    #expect(commands.first == SlashCommand(name: "/new", summary: "Start a new session (fresh session ID + history) (usage: /new [name])"))
    #expect(commands.contains { $0.name == "/compress" && !$0.isSkill })
    #expect(commands.contains(SlashCommand(name: "/crew-ui", summary: "Use for checklists, tables, charts, maps, forms, carousels.", isSkill: true)))
    #expect(commands.count == 119)
}

@Test func slashCatalogDropsCommandsDesktopHandlesElsewhere() throws {
    let names = Set(try recordedCatalog().map(\.name))
    #expect(names.isDisjoint(with: ["/clear", "/copy", "/paste", "/redraw", "/quit", "/model", "/voice", "/login", "/fast", "/mouse", "/compact", "/branch", "/resume"]))
}

@Test func slashPickerFiltersByPrefixIgnoringCase() throws {
    let commands = try recordedCatalog()
    let matches = SlashPicker(query: "RE", commands: commands) { _ in }.matches.map(\.name)
    #expect(matches == ["/retry", "/refine", "/review", "/reasoning", "/requesting-code-review"])
    #expect(SlashPicker(query: "", commands: commands) { _ in }.matches.count == commands.count)
    #expect(SlashPicker(query: "zzz", commands: commands) { _ in }.matches.isEmpty)
}

@Test func onlyAnExactCatalogNameRunsAsACommand() throws {
    let commands = try recordedCatalog()
    #expect(slashInvocation("/status", in: commands)?.command.name == "/status")
    #expect(slashInvocation("/status", in: commands)?.arg == "")
    let skill = slashInvocation("/humanizer  Rewrite this\nplease ", in: commands)
    #expect(skill?.command.isSkill == true)
    #expect(skill?.arg == "Rewrite this\nplease")
    #expect(slashInvocation("/foo", in: commands) == nil)
    #expect(slashInvocation("/statusx", in: commands) == nil)
    #expect(slashInvocation("/branch", in: commands) == nil)
    #expect(slashInvocation("what does /status show?", in: commands) == nil)
}

@Test func recordedSlashRepliesDecodeIntoTheirDirectives() throws {
    let replies = try recordedReplies()
    #expect(replies["/status"]?.type == nil)
    #expect(replies["/status"]?.output?.hasPrefix("Hermes TUI Status") == true)
    #expect(replies["/goal"]?.type == "exec")
    #expect(replies["/undo"]?.type == "prefill")
    #expect(replies["/undo"]?.notice?.contains("Undid 1 turn") == true)
    #expect(replies["/retry"]?.type == "send")
    #expect(replies["/retry"]?.message == "Can you do a new test purchase?")
}

@Test func anUndoneSkillTurnPrefillsTheTypedInvocation() throws {
    let message = try #require(try recordedReplies()["/undo"]?.message)
    #expect(Prompt(raw: message, sentAt: .now).text == "/humanizer Rewrite this in one short line: The system has been successfully updated.")
}

@Test func aSkillTurnInHistoryShowsTheTypedInvocation() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([HistoryRow].self, from: Data(contentsOf: fixtures.appending(path: "skill-invocation.history.json")))
    let turn = try #require(Transcript(history: rows).turns.first)
    #expect(turn.prompt?.text == "/humanizer Rewrite this in one short line: The system has been successfully updated.")
    #expect(turn.reply == "The system is updated.")
}

@Test func commandOutputStaysThroughAReloadWithoutBecomingThePreview() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let history = Transcript(turns: [
        Turn(id: "1", prompt: Prompt(text: "Hi", sentAt: start), reply: "Hello", status: .complete, startedAt: start, finishedAt: start.addingTimeInterval(2)),
        Turn(id: "2", prompt: Prompt(text: "Later", sentAt: start.addingTimeInterval(60)), reply: "Sure", status: .complete, startedAt: start.addingTimeInterval(60), finishedAt: start.addingTimeInterval(62)),
    ])
    var shown = Transcript(turns: [history.turns[0]])
    shown.beginCommand("/status", id: "c", at: start.addingTimeInterval(30))
    shown.finishCommand("c", output: "Hermes TUI Status\n", at: start.addingTimeInterval(31))
    #expect(shown.turns.last?.output == "Hermes TUI Status\n")
    #expect(shown.preview?.text == "Hello")
    var reloaded = history
    reloaded.keepCommands(from: shown)
    #expect(reloaded.turns.map(\.id) == ["1", "c", "2"])
    #expect(reloaded.preview?.text == "Sure")
}

@Test func aFailedCommandShowsHermesMessage() throws {
    var transcript = Transcript()
    transcript.beginCommand("/steer", id: "c")
    #expect(transcript.turns[0].finishedAt == nil)
    transcript.finishCommand("c", output: nil, failure: "usage: /steer <prompt>")
    #expect(transcript.turns[0].status == .error)
    #expect(transcript.turns[0].failure == "usage: /steer <prompt>")
    #expect(transcript.turns[0].notice == "/steer")
}
