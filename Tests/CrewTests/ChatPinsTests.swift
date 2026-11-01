import Foundation
import Testing

@MainActor private func scratchFile() -> URL {
    URL.temporaryDirectory.appending(path: "crew-pins-\(UUID().uuidString)/pins.json")
}

private let recipe = ChatPins.Card(surface: "recipe", source: #"{"createSurface":{"surfaceId":"recipe"}}"#, finishedAt: .now + 60)
private let route = ChatPins.Card(surface: "route", source: #"{"createSurface":{"surfaceId":"route"}}"#, finishedAt: .now + 120)

@MainActor @Test func aNewCardPinsAndANewerOneReplacesIt() {
    let pins = ChatPins(fileURL: scratchFile())
    pins.arrived(recipe, in: "chef")
    #expect(pins.pinned(in: "chef") == "recipe")
    pins.arrived(route, in: "chef")
    #expect(pins.pinned(in: "chef") == "route")
    #expect(pins.pinned(in: "scout") == nil)
}

@MainActor @Test func anUnpinnedCardStaysUnpinnedAfterARelaunch() {
    let file = scratchFile()
    let pins = ChatPins(fileURL: file)
    pins.arrived(recipe, in: "chef")
    pins.pin(nil, in: "chef")

    let relaunched = ChatPins(fileURL: file)
    relaunched.arrived(recipe, in: "chef")
    #expect(relaunched.pinned(in: "chef") == nil)
    relaunched.arrived(ChatPins.Card(surface: recipe.surface, source: recipe.source, finishedAt: recipe.finishedAt + 5), in: "chef")
    #expect(relaunched.pinned(in: "chef") == nil, "the same card reloaded from history with server time must not re-pin")
}

@MainActor @Test func anOlderCardArrivingAfterAnUnpinDoesNotPin() {
    let pins = ChatPins(fileURL: scratchFile())
    pins.arrived(route, in: "group:r1")
    pins.pin(nil, in: "group:r1")
    pins.arrived(recipe, in: "group:r1")
    #expect(pins.pinned(in: "group:r1") == nil)
}

@MainActor @Test func aReusedSurfaceIdWithANewBlockPinsAgain() {
    let pins = ChatPins(fileURL: scratchFile())
    pins.arrived(recipe, in: "chef")
    pins.pin(nil, in: "chef")
    pins.arrived(ChatPins.Card(surface: "recipe", source: #"{"createSurface":{"surfaceId":"recipe","vegan":true}}"#, finishedAt: recipe.finishedAt + 30), in: "chef")
    #expect(pins.pinned(in: "chef") == "recipe")
}

@MainActor @Test func cardsFromBeforeTheFileExistedNeverAutoPin() {
    let pins = ChatPins(fileURL: scratchFile())
    pins.arrived(ChatPins.Card(surface: "old", source: "{}", finishedAt: .now - 3600), in: "chef")
    #expect(pins.pinned(in: "chef") == nil)
    #expect(pins.chats["chef"] == nil)
}

@MainActor @Test func pinningAnOlderCardByHandUntilANewerOneArrives() {
    let file = scratchFile()
    let pins = ChatPins(fileURL: file)
    pins.arrived(recipe, in: "chef")
    pins.pin("menu", in: "chef")
    #expect(ChatPins(fileURL: file).pinned(in: "chef") == "menu")
    pins.arrived(recipe, in: "chef")
    #expect(pins.pinned(in: "chef") == "menu")
    pins.arrived(route, in: "chef")
    #expect(pins.pinned(in: "chef") == "route")
}

@MainActor @Test func deletingABotClearsOnlyItsPinAndSignOutClearsAll() {
    let file = scratchFile()
    let pins = ChatPins(fileURL: file)
    pins.arrived(recipe, in: "chef")
    pins.arrived(route, in: "scout")
    pins.clear("chef")
    #expect(ChatPins(fileURL: file).chats.keys.sorted() == ["scout"])
    pins.reset()
    #expect(ChatPins(fileURL: file).chats.isEmpty)
    pins.arrived(ChatPins.Card(surface: "old", source: "{}", finishedAt: .now - 60), in: "scout")
    #expect(pins.pinned(in: "scout") == nil, "Sign Out moves the watermark to now")
}
