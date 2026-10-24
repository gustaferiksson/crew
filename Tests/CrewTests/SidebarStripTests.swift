import AppKit
import SwiftUI
import Testing

private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/cold-open")
private let swiftUISidebarFloor: CGFloat = 140

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

private func peer(_ store: BotStore) throws -> Bot {
    try #require(store.bots.first { $0.name == "crew-test-peer" })
}

@MainActor private final class Frames {
    var sizes: [CGSize] = []
}

@MainActor private func rowSize(in listWidth: CGFloat, insets: EdgeInsets, @ViewBuilder row: () -> some View) -> CGSize? {
    let frames = Frames()
    let list = List {
        row()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { frames.sizes.append($0) }
            .listRowInsets(insets)
    }
    .listStyle(.sidebar)
    .frame(width: listWidth, height: 600)
    let window = NSWindow(contentRect: CGRect(x: -4000, y: 0, width: listWidth, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: list)
    window.contentView?.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.3))
    return frames.sizes.last
}

@MainActor private func textColumn(in sidebarWidth: CGFloat) throws -> CGFloat {
    let row = try #require(rowSize(in: sidebarWidth, insets: EdgeInsets(top: rowPadding, leading: 0, bottom: rowPadding, trailing: 12)) { Color.clear.frame(height: 1) })
    return row.width - dotGutter - rowAvatarSize - 12
}

@MainActor private func fitting(_ bot: Bot, _ store: BotStore) -> CGSize {
    NSHostingView(rootView: BotStripTile(bot: bot, photo: nil, isOpen: false).environment(store).environment(ChatSessions()).environment(ChatDrafts(fixture: [:]))).fittingSize
}

@MainActor private func width(_ text: Text) -> CGFloat {
    NSHostingView(rootView: text).fittingSize.width
}

@Test func theStripSitsBelowTheThresholdAndTheDefaultWidth() {
    #expect(stripWidth <= swiftUISidebarFloor)
    #expect(stripThreshold > swiftUISidebarFloor)
    #expect(stripThreshold < 320)
}

@Test @MainActor func theThresholdIsWhereARegularRowStopsHoldingANameBesideTheWidestStatus() throws {
    let needed = width(Text(verbatim: "Ada Lovelace").font(.headline)) + 4 + width(Text(verbatim: BotStatus.waiting(.approval).label ?? "").font(.subheadline))
    let atThreshold = try textColumn(in: stripThreshold)
    let below = try textColumn(in: stripThreshold - 8)
    #expect(atThreshold >= needed, "\(atThreshold) \(needed)")
    #expect(below < needed, "\(below) \(needed)")
}

@Test @MainActor func aStripTileHasMessagesProportions() throws {
    let unread = try store("after")
    #expect(fitting(try peer(unread), unread) == CGSize(width: 78, height: 86))
}

@Test @MainActor func aStripTileIsTheSameSizeWhateverTheStatusOrRole() throws {
    let unread = try store("after")
    let working = try store("working")
    #expect(ChatSessions().status(of: try peer(unread).id, in: unread) == .unread)
    #expect(ChatSessions().status(of: try peer(working).id, in: working) == .working)
    var roled = try peer(unread)
    roled.meta.role = "Head of Research and Analytics"

    let tile = fitting(try peer(unread), unread)
    #expect(fitting(try peer(working), working) == tile)
    #expect(fitting(roled, unread) == tile)
}
