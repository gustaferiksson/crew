import A2UICore
import Foundation
import OrderedJSON
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000)

nonisolated private struct SentPayload: Decodable {
    let name: String
    let surfaceId: String
    let sourceComponentId: String
    let context: [String: OrderedJSON.JSONValue]
}

@MainActor private func opened(_ block: String) -> (store: SurfaceStore, sent: () -> [String]) {
    let store = SurfaceStore()
    var sent: [String] = []
    store.send = { sent.append($0) }
    store.sync(Transcript(turns: [Turn(id: "t1", prompt: Prompt(text: "List", sentAt: start), reply: "Here.\n\n```a2ui\n\(block)\n```", status: .complete, startedAt: start, finishedAt: start)]))
    return (store, { sent })
}

@MainActor private func tap(_ buttonID: String, on surfaceID: String, in store: SurfaceStore) throws {
    let button = try #require(nodes(store.processor.surfaceGroupModel[surfaceID]?.rootNode).first { $0.type == "Button" && $0.id == buttonID })
    button.action(for: "action")?()
}

@MainActor private func payload(_ text: String?) throws -> SentPayload {
    let text = try #require(text)
    let json = try #require(text.firstMatch(of: /<a2ui-action>([\s\S]*)<\/a2ui-action>/)?.1)
    return try JSONDecoder().decode(SentPayload.self, from: Data(json.utf8))
}

private func skillShoppingList() throws -> String {
    let skill = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/Profile/crew-ui.SKILL.md"), encoding: .utf8)
    return try #require(markdownBlocks(from: skill).map { String($0.content.characters) }.first { $0.contains("taco-shopping-list") })
}

@MainActor @Test func theSkillShoppingListButtonSendsTheTickedItemsAtTapTime() throws {
    let (store, sent) = opened(try skillShoppingList())
    let boxes = nodes(store.processor.surfaceGroupModel["taco-shopping-list"]?.rootNode).filter { $0.type == "CheckBox" }
    for label in ["2 avocados", "8 tortillas"] {
        try #require(boxes.first { $0.string(for: "label") == label }).binding(for: "value", default: false).wrappedValue = true
    }

    try tap("done", on: "taco-shopping-list", in: store)

    let action = try payload(sent().last)
    #expect(action.surfaceId == "taco-shopping-list")
    let items = action.context.values.flatMap { $0.arrayValue ?? [] }
    let ticked = items.filter { $0["done"]?.boolValue == true }.compactMap { $0["name"]?.stringValue }
    #expect(ticked.sorted() == ["2 avocados", "8 tortillas"])
    #expect(items.count == 9, "every item comes with its tick, so the bot knows what is left")
}

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

@MainActor @Test func tickingTheRealBotsListAndTappingSendsWhatTheProbeSent() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.a2ui-action.history.json")
    let rows = try decoder.decode(HistoryFile.self, from: Data(contentsOf: file)).messages
    let tapped = try #require(rows.firstIndex { $0.displayKind == "hidden" })
    let recorded = try payload(rows[tapped].content)
    let store = SurfaceStore()
    var sent: [String] = []
    store.send = { sent.append($0) }
    store.sync(Transcript(history: Array(rows[..<tapped])))
    let boxes = nodes(store.processor.surfaceGroupModel[recorded.surfaceId]?.rootNode).filter { $0.type == "CheckBox" }
    let ticked = recorded.context.values.flatMap { $0.arrayValue ?? [] }.filter { $0["done"]?.boolValue == true }.compactMap { $0["name"]?.stringValue }
    try #require(ticked.count == 2)

    for label in ticked {
        try #require(boxes.first { $0.string(for: "label") == label }).binding(for: "value", default: false).wrappedValue = true
    }
    try tap(recorded.sourceComponentId, on: recorded.surfaceId, in: store)

    let action = try payload(sent.last)
    #expect(action.name == recorded.name)
    #expect(action.context == recorded.context, "Crew's tap builds the payload the probe sent to the real bot")
}

@MainActor @Test func aBoundValueOverTheLimitIsReplacedWhileTheRestIsSent() throws {
    let note = String(repeating: "a", count: 9000)
    let block = """
    [
      {"version": "v0.9", "createSurface": {"surfaceId": "notes", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
      {"version": "v0.9", "updateComponents": {"surfaceId": "notes", "components": [
        {"id": "root", "component": "Card", "child": "send"},
        {"id": "send", "component": "Button", "child": "send-label", "action": {"event": {"name": "save", "context": {"note": {"path": "/note"}, "short": {"path": "/short"}, "choice": "keep"}}}},
        {"id": "send-label", "component": "Text", "text": "Save"}
      ]}},
      {"version": "v0.9", "updateDataModel": {"surfaceId": "notes", "value": {"note": "\(note)", "short": "milk"}}}
    ]
    """
    let (store, sent) = opened(block)

    try tap("send", on: "notes", in: store)

    let action = try payload(sent().last)
    #expect(action.context["short"] == .string("milk"))
    #expect(action.context["choice"] == .string("keep"))
    #expect(action.context["note"] == .string("(not sent: over 8 KB)"))
    #expect(try #require(sent().last).utf8.count < 1024)
}
