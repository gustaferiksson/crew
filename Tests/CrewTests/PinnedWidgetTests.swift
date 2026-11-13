import Foundation
import Testing

@MainActor private func scratchFiles() -> (pins: URL, widget: URL) {
    let directory = URL.temporaryDirectory.appending(path: "crew-widget-\(UUID().uuidString)")
    return (directory.appending(path: "pins.json"), directory.appending(path: "group/pinned-cards.json"))
}

private let recipe = ChatPins.Card(surface: "recipe", source: #"{"createSurface":{"surfaceId":"recipe"}}"#, finishedAt: .now + 60)
private let route = ChatPins.Card(surface: "route", source: #"{"createSurface":{"surfaceId":"route"}}"#, finishedAt: .now + 120)

private func glance(_ surface: String, title: String = "Groceries", done: Int = 2) -> PinnedGlance {
    PinnedGlance(surface: surface, title: title, subtitle: nil, symbol: "cart", tone: "success", progress: .init(done: done, total: 6))
}

private func bot(_ name: String, hidden: Bool = false) -> VoiceBot {
    VoiceBot(name: name, title: name.capitalized, session: nil, lastActive: nil, shape: "blob", color: "#8b5cf6", expression: nil, hidden: hidden)
}

@MainActor @Test func theWidgetFileHoldsThePinnedCardAsTheChatShowsIt() {
    let files = scratchFiles()
    let pins = ChatPins(fileURL: files.pins, widgetURL: files.widget)
    pins.arrived(recipe, in: "chef")
    pins.show(glance("recipe"), in: "chef")

    let saved = PinnedGlance.saved(at: files.widget)
    #expect(saved["chef"]?.title == "Groceries")
    #expect(saved["chef"]?.progress == .init(done: 2, total: 6))

    pins.show(glance("recipe", done: 3), in: "chef")
    #expect(PinnedGlance.saved(at: files.widget)["chef"]?.progress?.done == 3)
}

@MainActor @Test func aCardThatIsNotPinnedNeverReachesTheWidget() {
    let files = scratchFiles()
    let pins = ChatPins(fileURL: files.pins, widgetURL: files.widget)
    pins.arrived(recipe, in: "chef")
    pins.show(glance("menu"), in: "chef")
    pins.show(glance("recipe"), in: "scout")
    #expect(PinnedGlance.saved(at: files.widget).isEmpty)
}

@MainActor @Test func everyWayAPinEndsRemovesItFromTheWidget() {
    let files = scratchFiles()
    let pins = ChatPins(fileURL: files.pins, widgetURL: files.widget)
    for chat in ["unpin", "newer", "by-hand", "deleted", "signed-out"] {
        pins.arrived(recipe, in: chat)
        pins.show(glance("recipe"), in: chat)
    }
    #expect(PinnedGlance.saved(at: files.widget).count == 5)

    pins.pin(nil, in: "unpin")
    pins.arrived(route, in: "newer")
    pins.pin("menu", in: "by-hand")
    pins.clear("deleted")
    #expect(Set(PinnedGlance.saved(at: files.widget).keys) == ["signed-out"])

    pins.reset()
    #expect(PinnedGlance.saved(at: files.widget).isEmpty)
    #expect(FileManager.default.fileExists(atPath: files.widget.path()))
}

@MainActor @Test func aRelaunchedStoreKeepsTheOtherChatsCards() {
    let files = scratchFiles()
    let pins = ChatPins(fileURL: files.pins, widgetURL: files.widget)
    pins.arrived(recipe, in: "chef")
    pins.show(glance("recipe"), in: "chef")

    let relaunched = ChatPins(fileURL: files.pins, widgetURL: files.widget)
    relaunched.arrived(route, in: "scout")
    relaunched.show(glance("route", title: "Hike"), in: "scout")
    #expect(PinnedGlance.saved(at: files.widget).mapValues(\.title) == ["chef": "Groceries", "scout": "Hike"])
}

@MainActor @Test func tickingKeepsTheTimeTheCardWasPinned() throws {
    let files = scratchFiles()
    let pins = ChatPins(fileURL: files.pins, widgetURL: files.widget)
    pins.arrived(recipe, in: "chef")
    pins.show(glance("recipe"), in: "chef")
    let pinnedAt = try #require(PinnedGlance.saved(at: files.widget)["chef"]?.pinnedAt)
    #expect(pinnedAt > .distantPast)

    pins.show(glance("recipe", done: 5), in: "chef")
    #expect(PinnedGlance.saved(at: files.widget)["chef"]?.pinnedAt == pinnedAt)
}

@MainActor @Test func storesWithoutAWidgetFileWriteNoGlances() {
    let files = scratchFiles()
    let pins = ChatPins(fileURL: files.pins, widgetURL: nil)
    pins.arrived(recipe, in: "chef")
    pins.show(glance("recipe"), in: "chef")
    #expect(pins.chats["chef"]?.glance == nil)
    #expect(!FileManager.default.fileExists(atPath: files.widget.path()))
}

@Test func theChosenBotShowsItsCardOrNone() {
    let bots = [bot("chef"), bot("scout")]
    let glances = ["chef": glance("recipe")]
    #expect(PinnedWidgetContent(bot: "chef", bots: bots, glances: glances) == .bot(bots[0], glances["chef"]))
    #expect(PinnedWidgetContent(bot: "scout", bots: bots, glances: glances) == .bot(bots[1], nil))
    #expect(PinnedWidgetContent(bot: "gone", bots: bots, glances: glances) == .missingBot)
    #expect(PinnedWidgetContent(bot: "chef", bots: [], glances: glances) == .signedOut)
}

@Test func withoutAChoiceTheNewestPinOfAListedBotShows() {
    var old = glance("recipe")
    old.pinnedAt = Date(timeIntervalSince1970: 100)
    var newer = glance("route", title: "Hike")
    newer.pinnedAt = Date(timeIntervalSince1970: 200)
    var newest = glance("secret", title: "Gifts")
    newest.pinnedAt = Date(timeIntervalSince1970: 300)
    let glances = ["chef": old, "scout": newer, "ghost": newest, "group:r1": newest, "removed": newest]
    let bots = [bot("chef"), bot("scout"), bot("ghost", hidden: true)]

    #expect(PinnedWidgetContent(bot: nil, bots: bots, glances: glances) == .bot(bots[1], newer))
    #expect(PinnedWidgetContent(bot: nil, bots: [bots[0], bots[2]], glances: glances) == .bot(bots[0], old))
    #expect(PinnedWidgetContent(bot: nil, bots: [bots[2]], glances: glances) == .noPins)
    #expect(PinnedWidgetContent(bot: nil, bots: [], glances: glances) == .signedOut)
}
