import Foundation
import Observation

private let requiredMethods: Set = ["groups.list", "groups.create", "groups.state", "groups.log", "groups.send", "groups.stop", "groups.approve"]

nonisolated struct RoomMember: Codable, Hashable, Sendable {
    let memberID: String
    let profile: String
    let handle: String
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case profile, handle
        case memberID = "member_id"
        case displayName = "display_name"
    }
}

nonisolated struct Room: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let members: [RoomMember]
    let createdAt: Date
    let updatedAt: Date

    var selectionID: String { "group:\(id)" }

    private enum CodingKeys: String, CodingKey {
        case name, members
        case id = "room_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated private struct RoomCapabilities: Decodable, Sendable {
    let driver: Bool
    let methods: [String]
}

nonisolated private struct RoomList: Decodable, Sendable {
    let rooms: [Room]
}

nonisolated private struct CreatedRoom: Decodable, Sendable {
    let room: Room
}

nonisolated private struct CreateRoomParams: Encodable, Sendable {
    let roomID: String
    let name: String
    let members: [RoomMember]

    private enum CodingKeys: String, CodingKey {
        case name, members
        case roomID = "room_id"
    }
}

@Observable
final class GroupStore {
    private(set) var rooms: [Room] = []
    private(set) var isSupported = false

    init() {}

    init(fixture rooms: [Room]) {
        self.rooms = rooms
        isSupported = true
    }

    func run(_ gateway: Gateway) async {
        let events = gateway.events()
        if await gateway.status == .connected { await check(gateway) }
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await event in events where event.type == "gateway.ready" {
                    await self.check(gateway)
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    await self.reload(gateway)
                }
            }
        }
    }

    func create(named name: String, with bots: [Bot], via gateway: Gateway) async throws -> Room {
        let members = bots.map { RoomMember(memberID: $0.name, profile: $0.name, handle: $0.handle, displayName: $0.title) }
        let params = CreateRoomParams(roomID: "room-\(UUID().uuidString.lowercased())", name: name, members: members)
        let room = try await gateway.call("groups.create", params, as: CreatedRoom.self).room
        rooms.insert(room, at: 0)
        return room
    }

    func reset() {
        rooms = []
        isSupported = false
    }

    private func check(_ gateway: Gateway) async {
        let capabilities = try? await gateway.call("groups.capabilities", [String: String](), as: RoomCapabilities.self)
        isSupported = capabilities.map { $0.driver && requiredMethods.isSubset(of: $0.methods) } ?? false
        guard isSupported else { return rooms = [] }
        await reload(gateway)
    }

    private func reload(_ gateway: Gateway) async {
        guard isSupported, let list = try? await gateway.call("groups.list", [String: String](), as: RoomList.self) else { return }
        if list.rooms != rooms { rooms = list.rooms }
    }
}
