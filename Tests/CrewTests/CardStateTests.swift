import A2UICore
import Foundation
import OrderedJSON
import SwiftUI
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private let recipe = "kottbullar-for-four"

private func rows(_ name: String) throws -> [HistoryRow] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/\(name)")
    return try decoder.decode(HistoryFile.self, from: Data(contentsOf: file)).messages
}

private func scratchFile() -> URL {
    URL.temporaryDirectory.appending(path: "crew-cards-\(UUID().uuidString)/cards.json")
}

@MainActor private func opened(_ transcript: Transcript, from file: URL) -> SurfaceStore {
    let store = SurfaceStore()
    store.saved = (CardState(fileURL: file), "chef")
    store.sync(transcript)
    return store
}

@MainActor private func tick(_ label: String, in store: SurfaceStore, to value: Bool = true) throws {
    let box = try #require(nodes(store.processor.surfaceGroupModel[recipe]?.rootNode).first { $0.type == "CheckBox" && $0.string(for: "label")?.hasSuffix(label) == true })
    box.binding(for: "value", default: false).wrappedValue = value
}

@MainActor private func isTicked(_ label: String, in store: SurfaceStore) throws -> Bool {
    let box = try #require(nodes(store.processor.surfaceGroupModel[recipe]?.rootNode).first { $0.type == "CheckBox" && $0.string(for: "label")?.hasSuffix(label) == true })
    return box.binding(for: "value", default: false).wrappedValue
}

@MainActor @Test func aTickAndTheServingsSurviveARelaunch() throws {
    let file = scratchFile()
    let transcript = Transcript(history: try rows("chat.a2ui-servings.history.json"))
    let store = opened(transcript, from: file)
    try tick("250 g beef mince", in: store)
    let stepper = try #require(nodes(store.processor.surfaceGroupModel[recipe]?.rootNode).first { $0.type == "Stepper" })
    stepper.binding(for: "value", default: 0.0).wrappedValue = 6

    let relaunched = opened(transcript, from: file)
    #expect(try isTicked("beef mince", in: relaunched))
    #expect(!(try isTicked("pork mince", in: relaunched)))
    #expect(relaunched.processor.surfaceGroupModel[recipe]?.dataModel.get("/servings")?.numeric == 6)
    let labels = nodes(relaunched.processor.surfaceGroupModel[recipe]?.rootNode).filter { $0.type == "CheckBox" }.compactMap { $0.string(for: "label") }
    #expect(labels.first == "375 g beef mince", "the restored servings rescale the amounts")

    let saved = try #require(CardState(fileURL: file).chats["chef"]?.values.first?.values)
    #expect(saved.keys.sorted() == ["/meat/0/done", "/servings"], "only what the user changed, never the bot's data")
}

@MainActor @Test func aBotUpdateOverridesOnlyThePathsItSends() throws {
    let file = scratchFile()
    let all = try rows("chat.a2ui-update.history.json")
    let prompts = all.indices.filter { all[$0].role == "user" }
    let store = opened(Transcript(history: Array(all[..<prompts[2]])), from: file)
    try tick("375 g minced beef", in: store)
    let sauce = try #require(nodes(store.processor.surfaceGroupModel[recipe]?.rootNode).first { $0.type == "CheckBox" && $0.id.contains("gravy") }?.string(for: "label"))
    try tick(sauce, in: store)

    store.sync(Transcript(history: Array(all[..<prompts[3]])))
    #expect(!(try isTicked("375 g minced beef", in: store)), "the bot's tick-off resent /meat, so its value wins")
    #expect(try isTicked("fine dried breadcrumbs", in: store), "the bot's own tick shows")
    #expect(try isTicked(sauce, in: store), "a path the bot did not send keeps the user's tick")

    let relaunched = opened(Transcript(history: all), from: file)
    #expect(!(try isTicked("375 g minced beef", in: relaunched)))
    #expect(try isTicked(sauce, in: relaunched))
}

@MainActor @Test func aTickAfterTheBotsUpdateSurvivesReplayingThatUpdate() throws {
    let file = scratchFile()
    let all = try rows("chat.a2ui-update.history.json")
    let store = opened(Transcript(history: all), from: file)
    try tick("fine dried breadcrumbs", in: store, to: false)

    let relaunched = opened(Transcript(history: all), from: file)
    #expect(!(try isTicked("fine dried breadcrumbs", in: relaunched)), "replaying the tick-off it already saw drops nothing")
}

@MainActor @Test func aSameIdRecreateStartsFresh() throws {
    let file = scratchFile()
    let all = try rows("chat.a2ui-update.history.json")
    let prompts = all.indices.filter { all[$0].role == "user" }
    let store = opened(Transcript(history: Array(all[..<prompts[1]])), from: file)
    try tick("250 g minced beef", in: store)

    store.sync(Transcript(history: Array(all[..<prompts[2]])))
    #expect(!(try isTicked("375 g minced beef", in: store)))
    #expect(!(try isTicked("375 g minced beef", in: opened(Transcript(history: Array(all[..<prompts[2]])), from: file))))
}

@MainActor @Test func clearAndResetEmptyTheFileAndTheOldestCardsGoFirst() throws {
    let file = scratchFile()
    let cards = CardState(fileURL: file)
    cards.userChanged(["/a": .boolean(true)], on: "one", after: [], in: "chef")
    cards.userChanged(["/a": .boolean(true)], on: "two", after: [], in: "scout")
    cards.clear("chef")
    #expect(CardState(fileURL: file).chats.keys.sorted() == ["scout"])
    cards.reset()
    #expect(CardState(fileURL: file).chats.isEmpty)

    for index in 0...CardState.limit {
        cards.userChanged(["/a": .integer(index)], on: "card-\(index)", after: [], in: "chef")
    }
    let kept = try #require(CardState(fileURL: file).chats["chef"])
    #expect(kept.count == CardState.limit)
    #expect(kept["card-0"] == nil)
    #expect(kept["card-\(CardState.limit)"] != nil)
}
