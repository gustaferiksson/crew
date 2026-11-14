import Foundation
import Testing

nonisolated private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

nonisolated private func route(_ path: String) throws -> PushRoute {
    let payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appending(path: path))) as? [AnyHashable: Any])
    return try #require(PushRoute(userInfo: payload))
}

@Test func roomPushOpensTheRoom() throws {
    let room = try route("rooms/push-room-reply.json")
    #expect(room.profile == "crew-test")
    #expect(room.roomID == "room-9b04759b-41ca-4a2a-83a2-3092a4fbc686")
    #expect(room.selectionID == "group:room-9b04759b-41ca-4a2a-83a2-3092a4fbc686")
}

@Test func botChatPushStillOpensTheBot() throws {
    let bot = try route("payments/push-payment.json")
    #expect(bot.roomID == nil)
    #expect(bot.selectionID == "scout")
}

@MainActor @Test func roomPushIsQuietOnlyWhileThatRoomIsOnScreen() throws {
    let room = try route("rooms/push-room-reply.json")
    #expect(PushCenter.presentation(for: room, isActive: true, visibleBot: "group:room-9b04759b-41ca-4a2a-83a2-3092a4fbc686") == [])
    #expect(PushCenter.presentation(for: room, isActive: true, visibleBot: "crew-test") == [.banner, .list, .sound])
    #expect(PushCenter.presentation(for: room, isActive: false, visibleBot: "group:room-9b04759b-41ca-4a2a-83a2-3092a4fbc686") == [.banner, .list, .sound])
    #expect(PushCenter.presentation(for: try route("payments/push-payment.json"), isActive: true, visibleBot: "scout") == [])
}
