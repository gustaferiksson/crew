import A2UICore
import Foundation
import OrderedJSON
import SwiftUI
import Testing

private func nodes(_ node: Node?) -> [Node] {
    guard let node else { return [] }
    let children = node.properties.values.flatMap { value in (value as? Node).map { [$0] } ?? (value as? [Node]) ?? [] }
    return [node] + children.flatMap(nodes)
}

@MainActor private func surface(_ block: String) throws -> SurfaceViewModel {
    let payload = try JSONDecoder().decode(OrderedJSON.JSONValue.self, from: Data(block.utf8))
    let processor = MessageProcessor(catalogs: crewCatalogs)
    try processor.processMessages(payload)
    let id = try #require(payload.arrayValue?.compactMap { $0["createSurface"]?["surfaceId"]?.stringValue }.first)
    return try #require(processor.surfaceGroupModel[id])
}

@MainActor private func labels(_ model: SurfaceViewModel) -> [String] {
    nodes(model.rootNode).filter { $0.type == "CheckBox" }.map { $0.string(for: "label") ?? "" }
}

@MainActor private func turnStepper(_ model: SurfaceViewModel, to servings: Double) throws {
    let stepper = try #require(nodes(model.rootNode).first { $0.type == "Stepper" })
    stepper.binding(for: "value", default: 0.0).wrappedValue = servings
}

private func skillRecipe() throws -> String {
    let skill = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/Profile/crew-ui.SKILL.md"), encoding: .utf8)
    let blocks = markdownBlocks(from: skill).filter { $0.kind == .code(language: "a2ui") }.map { String($0.content.characters) }
    return try #require(blocks.first { $0.contains(#""component": "Stepper""#) })
}

@MainActor @Test func theSkillRecipeRescalesEveryIngredientWhenTheStepperTurns() throws {
    let model = try surface(skillRecipe())
    #expect(labels(model) == ["2½ dl vetemjöl", "6 dl mjölk", "3 ägg", "½ tsk salt", "smör till stekning"], "as written at the bot's servings")

    try turnStepper(model, to: 6)
    #expect(labels(model) == ["3¾ dl vetemjöl", "9 dl mjölk", "5 ägg", "¾ tsk salt", "smör till stekning"])
    #expect(nodes(model.rootNode).first { $0.type == "Stepper" }?.double(for: "value") == 6)

    try turnStepper(model, to: 2)
    #expect(labels(model) == ["1¼ dl vetemjöl", "3 dl mjölk", "1½ ägg", "¼ tsk salt", "smör till stekning"])

    try turnStepper(model, to: 1)
    #expect(labels(model) == ["⅔ dl vetemjöl", "1½ dl mjölk", "1 ägg", "¼ tsk salt", "smör till stekning"])
}

@MainActor @Test func aPartialCardWithoutItsDataStillBuilds() throws {
    let messages = try #require(try JSONDecoder().decode(OrderedJSON.JSONValue.self, from: Data(skillRecipe().utf8)).arrayValue)
    let partial = try JSONEncoder().encode(OrderedJSON.JSONValue.array(messages.filter { $0["updateDataModel"] == nil }))
    let model = try surface(String(decoding: partial, as: UTF8.self))
    #expect(labels(model).isEmpty)
    #expect(nodes(model.rootNode).first { $0.type == "Stepper" }?.binding(for: "value", default: 1.0).wrappedValue == 1, "a missing servings path shows min")
}

@Test func amountsRoundTheWayCookbooksWriteThem() {
    #expect(scaledAmount(500, from: 4, to: 6, unit: "g", item: "blandfärs", one: "") == "750 g blandfärs")
    #expect(scaledAmount(500, from: 4, to: 3, unit: "g", item: "blandfärs", one: "") == "375 g blandfärs")
    #expect(scaledAmount(33, from: 4, to: 6, unit: "g", item: "smör", one: "") == "50 g smör")
    #expect(scaledAmount(530, from: 4, to: 10, unit: "g", item: "mjöl", one: "") == "1350 g mjöl")
    #expect(scaledAmount(1, from: 4, to: 6, unit: "cups", item: "milk", one: "cup milk") == "1½ cups milk")
    #expect(scaledAmount(1, from: 3, to: 2, unit: "cups", item: "milk", one: "cup milk") == "⅔ cup milk")
    #expect(scaledAmount(2, from: 4, to: 2, unit: "", item: "eggs", one: "egg") == "1 egg")
    #expect(scaledAmount(2, from: 4, to: 5, unit: "", item: "eggs", one: "egg") == "2½ eggs", "countables round to halves, ties up")
    #expect(scaledAmount(1, from: 4, to: 1, unit: "", item: "lökar", one: "lök") == "½ lök", "never zero")
    #expect(scaledAmount(6, from: 4, to: 12, unit: "dl", item: "mjölk", one: "") == "18 dl mjölk")
}

@Test func theBotsAmountsShowAsWrittenAndBadInputNeverBreaksTheRow() {
    #expect(scaledAmount(33, from: 4, to: 4, unit: "g", item: "smör", one: "") == "33 g smör")
    #expect(scaledAmount(1.2, from: 4, to: 4, unit: "kg", item: "potatis", one: "") != "1¼ kg potatis")
    #expect(scaledAmount(nil, from: 4, to: 6, unit: "", item: "salt och peppar", one: "") == "salt och peppar")
    #expect(scaledAmount(2, from: 0, to: 6, unit: "dl", item: "grädde", one: "") == "2 dl grädde")
    #expect(scaledAmount(2, from: 4, to: nil, unit: "dl", item: "grädde", one: "") == "2 dl grädde")
}

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

@MainActor @Test func theRealBotsKottbullarCardRescalesOnDevice() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/chat.a2ui-servings.history.json")
    let store = SurfaceStore()
    store.sync(Transcript(history: try decoder.decode(HistoryFile.self, from: Data(contentsOf: file)).messages))
    let model = try #require(store.processor.surfaceGroupModel["kottbullar-for-four"])

    #expect(labels(model) == [
        "250 g beef mince", "250 g pork mince", "50 g fine dried breadcrumbs", "100 ml milk", "1 small onion, finely chopped", "1 egg",
        "¾ tsp fine salt", "¼ tsp ground black pepper", "¼ tsp ground allspice (optional)", "2 tbsp butter for onion and frying",
        "1 tbsp butter", "1½ tbsp plain flour", "300 ml beef stock, preferably low-salt", "150 ml double or whipping cream", "1 tsp soy sauce",
        "Salt and black pepper, to taste", "800 g potatoes", "Lingonberry jam", "Pickled cucumber",
    ])

    try turnStepper(model, to: 6)
    #expect(labels(model) == [
        "375 g beef mince", "375 g pork mince", "75 g fine dried breadcrumbs", "150 ml milk", "1½ small onions, finely chopped", "1½ eggs",
        "1¼ tsp fine salt", "⅓ tsp ground black pepper", "⅓ tsp ground allspice (optional)", "3 tbsp butter for onion and frying",
        "1½ tbsp butter", "2¼ tbsp plain flour", "450 ml beef stock, preferably low-salt", "225 ml double or whipping cream", "1½ tsp soy sauce",
        "Salt and black pepper, to taste", "1200 g potatoes", "Lingonberry jam", "Pickled cucumber",
    ])

    try turnStepper(model, to: 2)
    #expect(labels(model) == [
        "125 g beef mince", "125 g pork mince", "25 g fine dried breadcrumbs", "50 ml milk", "½ small onion, finely chopped", "½ egg",
        "⅓ tsp fine salt", "¼ tsp ground black pepper", "¼ tsp ground allspice (optional)", "1 tbsp butter for onion and frying",
        "½ tbsp butter", "¾ tbsp plain flour", "150 ml beef stock, preferably low-salt", "75 ml double or whipping cream", "½ tsp soy sauce",
        "Salt and black pepper, to taste", "400 g potatoes", "Lingonberry jam", "Pickled cucumber",
    ])
}
