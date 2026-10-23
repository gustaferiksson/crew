import AppKit
import SwiftUI
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/cold-open")

private func recorded<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
    try JSONDecoder().decode(type, from: Data(contentsOf: scenario.appending(path: "\(name).json")))
}

private func store(_ phase: String) throws -> BotStore {
    let store = BotStore(fixture: [], statuses: [:])
    store.apply(roster: try recorded("profiles.before", as: Roster.self).profiles)
    store.apply(roster: try recorded("profiles.\(phase)", as: Roster.self).profiles)
    store.apply(live: try recorded("active_list.\(phase)", as: ActiveList.self).sessions)
    return store
}

@MainActor private func row(in sidebarWidth: CGFloat, _ store: BotStore) throws -> (height: CGFloat, idealWidth: CGFloat) {
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    let row = BotRow(bot: bot, photo: nil, isOpen: false, isCompact: sidebarWidth < compactRowWidth)
        .environment(store)
        .environment(ChatSessions())
        .environment(ChatDrafts(fixture: [:]))
    let height = NSHostingController(rootView: row).sizeThatFits(in: CGSize(width: sidebarWidth, height: 1000)).height
    return (height, NSHostingView(rootView: row).fittingSize.width)
}

@MainActor private func nameWidth(_ store: BotStore) throws -> CGFloat {
    let bot = try #require(store.bots.first { $0.name == "crew-test-peer" })
    return NSHostingView(rootView: Text(bot.title).font(.headline)).fittingSize.width
}

@Test func theThresholdSitsBetweenTheSidebarMinimumAndItsDefault() {
    #expect(compactRowWidth > 240)
    #expect(compactRowWidth < 320)
}

@Test @MainActor func aNarrowSidebarShowsOnlyTheAvatarAndName() throws {
    let unread = try store("after")
    let avatarAndName = dotGutter + rowAvatarSize + 12 + (try nameWidth(unread))

    let narrow = try row(in: compactRowWidth - 1, unread)
    #expect(narrow.height == rowAvatarSize, "\(narrow)")
    #expect(abs(narrow.idealWidth - avatarAndName) < 1, "\(narrow) \(avatarAndName)")

    let wide = try row(in: compactRowWidth, unread)
    #expect(wide.height > rowAvatarSize, "\(wide)")
    #expect(wide.idealWidth > avatarAndName + 40, "\(wide) \(avatarAndName)")
}

@Test @MainActor func aNarrowRowLaysOutNoStatusLabel() throws {
    let unread = try store("after")
    let working = try store("working")
    #expect(ChatSessions().summary(of: unread.bots[0], in: unread).status == .unread)
    #expect(ChatSessions().summary(of: working.bots[0], in: working).status == .working)

    #expect(try row(in: compactRowWidth - 1, working).idealWidth == row(in: compactRowWidth - 1, unread).idealWidth)
    #expect(try row(in: compactRowWidth, working).idealWidth != row(in: compactRowWidth, unread).idealWidth)
}
