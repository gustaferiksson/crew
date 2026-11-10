import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())
private let screenshot = "/opt/data/profiles/crew-test/home/.config/browser-harness/tmp/p-c322a189d25a/shot.png"

private func tools(_ transcript: Transcript) -> [ToolCall] {
    transcript.turns.last?.work.compactMap { if case .tool(let call) = $0.kind { call } else { nil } } ?? []
}

private func event(_ json: String) throws -> GatewayEvent {
    try JSONDecoder().decode(GatewayEvent.self, from: Data(json.utf8))
}

@MainActor @Test func aLiveScreenshotShowsOnItsToolRow() throws {
    var start = Transcript()
    start.begin(prompt: "Use your browser_exec tool to open https://example.com and take a screenshot of the page.")
    let session = ChatSession(fixture: crewTest, transcript: start, todos: [])
    let recording = try String(contentsOf: fixtures.appending(path: "chat.screenshot-turn.v0.23.0.jsonl"), encoding: .utf8)
    for line in recording.split(separator: "\n") {
        session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(line.utf8)))
    }

    #expect(tools(session.transcript).map(\.name) == ["browser_exec", "browser_exec", "browser_exec"])
    #expect(tools(session.transcript).map(\.image?.path) == [nil, nil, screenshot])
    #expect(tools(session.transcript).last?.image?.name == "shot.png")
}

@Test func aStoredScreenshotShowsOnItsToolRowAfterReopening() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([HistoryRow].self, from: Data(contentsOf: fixtures.appending(path: "chat.screenshot.history.v0.23.0.json")))

    #expect(tools(Transcript(history: rows)).map(\.image?.path) == [nil, nil, screenshot])
}

@MainActor @Test func toolProgressShowsOnTheRunningRowUntilItCompletes() throws {
    var start = Transcript()
    start.begin(prompt: "Index the docs.")
    let session = ChatSession(fixture: crewTest, transcript: start, todos: [])
    session.apply(try event(#"{"type":"message.start","payload":{}}"#))
    session.apply(try event(#"{"type":"tool.start","payload":{"tool_id":"call_1","name":"mcp_docs_index","args":{}}}"#))
    session.apply(try event(#"{"type":"tool.progress","payload":{"tool_id":"call_1","name":"mcp_docs_index","progress":3,"total":10,"percent":30,"message":"Indexing page 3 of 10"}}"#))

    #expect(tools(session.transcript).first?.percent == 30)
    #expect(tools(session.transcript).first?.progressMessage == "Indexing page 3 of 10")

    session.apply(try event(#"{"type":"tool.progress","payload":{"tool_id":"call_1","name":"mcp_docs_index","progress":4,"total":null,"percent":null,"message":"Still indexing"}}"#))
    session.apply(try event(#"{"type":"tool.progress","payload":{"tool_id":"","name":"mcp_docs_index","progress":5,"total":10,"percent":50,"message":null}}"#))

    #expect(tools(session.transcript).first?.percent == nil)
    #expect(tools(session.transcript).first?.progressMessage == "Still indexing")

    session.apply(try event(#"{"type":"tool.complete","payload":{"tool_id":"call_1","name":"mcp_docs_index","result":"{}"}}"#))
    session.apply(try event(#"{"type":"tool.progress","payload":{"tool_id":"call_1","name":"mcp_docs_index","progress":10,"total":10,"percent":100,"message":"Done"}}"#))

    #expect(tools(session.transcript).first?.status == .success)
    #expect(tools(session.transcript).first?.percent == nil)
    #expect(tools(session.transcript).first?.progressMessage == nil)
}

@Test func toolProgressLeavesATakenSteerForTheNextText() {
    var transcript = Transcript()
    transcript.begin(prompt: "Index the docs.")
    transcript.apply(.toolStart(id: "a", name: "terminal", context: nil, arguments: "{}"))
    transcript.wait(Prompt(text: "Skip the changelog.", sentAt: .now), as: .steer)
    transcript.apply(.toolComplete(id: "a", duration: 1, summary: nil, result: "{}"))
    transcript.apply(.toolStart(id: "b", name: "mcp_docs_index", context: nil, arguments: "{}"))
    transcript.apply(.toolProgress(id: "b", percent: 40, message: nil))

    #expect(transcript.turns.count == 1)
    #expect(tools(transcript).last?.percent == 40)
    #expect(transcript.waiting.map(\.pending) == [.taken])
}
