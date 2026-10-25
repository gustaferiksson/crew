import Foundation
import Testing

private func bot(_ name: String, minutesAgo: Double, _ meta: BotMeta) -> Bot {
    let session = StoredSessionID(rawValue: "s-\(name)")
    return Bot(
        name: name, displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false,
        canonicalSession: CanonicalSession(id: session, resolvedID: session, preview: nil, lastActive: .now.addingTimeInterval(-minutesAgo * 60), messageCount: 1),
        meta: meta, metaRevision: 1
    )
}

@MainActor @Test func hiddenBotsLeaveFavouritesAndSectionsForTheHiddenSection() {
    let store = BotStore(fixture: [
        bot("ada", minutesAgo: 5, BotMeta(pinned: true)),
        bot("ghost", minutesAgo: 30, BotMeta(pinned: true, hidden: true)),
        bot("forge", minutesAgo: 10, BotMeta(sectionID: "work", sectionName: "Work")),
        bot("shade", minutesAgo: 1, BotMeta(hidden: true, sectionID: "work", sectionName: "Work")),
        bot("quill", minutesAgo: 60, BotMeta(hidden: false)),
    ], statuses: ["ghost": .unread])
    #expect(store.favourites.map(\.id) == ["ada"])
    #expect(store.sections.flatMap(\.bots).map(\.id) == ["forge", "quill"])
    #expect(store.hiddenBots.map(\.id) == ["ghost", "shade"])
}

@MainActor @Test func hiddenSectionIsUnreadOnlyWhileAHiddenBotIsUnread() {
    let bots = [
        bot("ada", minutesAgo: 5, BotMeta()),
        bot("ghost", minutesAgo: 30, BotMeta(hidden: true)),
        bot("shade", minutesAgo: 1, BotMeta(hidden: true)),
    ]
    #expect(BotStore(fixture: bots, statuses: ["ghost": .unread, "shade": .working]).hasUnreadHidden)
    #expect(!BotStore(fixture: bots, statuses: ["ada": .unread, "shade": .waiting(.approval)]).hasUnreadHidden)
    #expect(!BotStore(fixture: bots, statuses: [:]).hasUnreadHidden)
}
