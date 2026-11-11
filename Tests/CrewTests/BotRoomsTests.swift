import Foundation
import Testing

nonisolated private struct RecordedList: Decodable {
    let rooms: [Room]
}

private func recordedRooms() throws -> [Room] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../fixtures/rooms/list.json").standardized
    return try decoder.decode(RecordedList.self, from: Data(contentsOf: url)).rooms
}

private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

@MainActor @Test func aBotListsOnlyTheRoomsItSitsInInServerOrder() throws {
    let rooms = try recordedRooms()
    let store = GroupStore(fixture: rooms)

    #expect(rooms.map(\.name) == ["Crew list peers", "Crew list two", "Crew list one"])
    #expect(store.rooms(with: crewTest).map(\.name) == ["Crew list two", "Crew list one"])
}

@MainActor @Test func aPeerNamesakeOnAnotherGatewayIsNotThisBot() throws {
    let recorded = try #require(try recordedRooms().first { $0.name == "Crew list peers" })
    let namesake = RoomMember(memberID: "crew-test@mini", profile: "crew-test", handle: "crew-test-mini", displayName: "Mini Crew Test", target: .init(kind: "peer"))
    let room = Room(id: recorded.id, name: recorded.name, members: recorded.members + [namesake], createdAt: recorded.createdAt, updatedAt: recorded.updatedAt)

    #expect(GroupStore(fixture: [room]).rooms(with: crewTest).isEmpty)
}

@MainActor @Test func aServerWithoutRoomsListsNone() {
    #expect(GroupStore().rooms(with: crewTest).isEmpty)
}
