import Foundation
import Testing

nonisolated private struct RecordedRooms: Decodable {
    let rooms: [Room]
}

private func recordedRooms() throws -> [Room] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../fixtures/rooms/list.json").standardized
    return try decoder.decode(RecordedRooms.self, from: Data(contentsOf: url)).rooms
}

@MainActor private func scratchFile() -> URL {
    URL.temporaryDirectory.appending(path: "crew-room-layout-\(UUID().uuidString)/room-layout.json")
}

private func bot(_ name: String, _ meta: BotMeta) -> Bot {
    Bot(name: name, displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: meta)
}

private let work = SectionTag(id: "work", name: "Work")

@MainActor @Test func aPinnedRoomIsAFavouriteAndLeavesOther() throws {
    let rooms = try recordedRooms()
    let layout = RoomLayout(fileURL: scratchFile())
    let store = BotStore(fixture: [bot("crew-test", BotMeta())], statuses: [:])

    layout.togglePin(rooms[1])

    #expect(layout.pinned(rooms).map(\.name) == ["Crew list two"])
    let sections = layout.sections(merging: store.sections, rooms: rooms)
    #expect(sections.map(\.id) == [""])
    #expect(layout.rooms(in: sections[0], of: rooms).map(\.name) == ["Crew list peers", "Crew list one"])
}

@MainActor @Test func aFiledRoomSitsInItsBotSectionUnderTheBotsName() throws {
    let rooms = try recordedRooms()
    let layout = RoomLayout(fileURL: scratchFile())
    let store = BotStore(fixture: [bot("crew-test", BotMeta(sectionID: "work", sectionName: "Work Renamed")), bot("quill", BotMeta())], statuses: [:])

    layout.move(rooms[0], to: work)

    let sections = layout.sections(merging: store.sections, rooms: rooms)
    #expect(sections.map(\.name) == ["Work Renamed", "Other"])
    #expect(layout.rooms(in: sections[0], of: rooms).map(\.name) == ["Crew list peers"])
    #expect(layout.rooms(in: sections[1], of: rooms).map(\.name) == ["Crew list two", "Crew list one"])
    #expect(layout.sectionTags(merging: store.sectionTags, rooms: rooms) == [SectionTag(id: "work", name: "Work Renamed")])
}

@MainActor @Test func aRoomKeepsASectionAliveAfterItsLastBotLeaves() throws {
    let rooms = try recordedRooms()
    let layout = RoomLayout(fileURL: scratchFile())
    let home = SectionTag(id: "sec-home", name: "Home")
    layout.move(rooms[2], to: home)
    layout.move(rooms[0], to: work)
    let store = BotStore(fixture: [bot("crew-test", BotMeta())], statuses: [:])

    let sections = layout.sections(merging: store.sections, rooms: rooms)

    #expect(sections.map(\.name) == ["Home", "Work", "Other"])
    #expect(sections.map { layout.rooms(in: $0, of: rooms).map(\.name) } == [["Crew list one"], ["Crew list peers"], ["Crew list two"]])
    #expect(layout.sectionTags(merging: store.sectionTags, rooms: rooms).map(\.name) == ["Home", "Work"])
}

@MainActor @Test func unpinningAFiledRoomReturnsItToItsSectionAndRemoveSendsItToOther() throws {
    let rooms = try recordedRooms()
    let layout = RoomLayout(fileURL: scratchFile())
    layout.move(rooms[0], to: work)
    layout.togglePin(rooms[0])
    #expect(layout.sections(merging: [], rooms: [rooms[0]]).isEmpty)

    layout.togglePin(rooms[0])
    #expect(layout.sections(merging: [], rooms: [rooms[0]]).map(\.name) == ["Work"])

    layout.move(rooms[0], to: nil)
    let sections = layout.sections(merging: [], rooms: [rooms[0]])
    #expect(sections.map(\.id) == [""])
    #expect(sections[0].name == nil)
    #expect(layout.entries.isEmpty)
}

@MainActor @Test func theLayoutSurvivesARelaunchAndAnEmptyRoomListAndClearsOnDisbandAndSignOut() throws {
    let rooms = try recordedRooms()
    let file = scratchFile()
    let layout = RoomLayout(fileURL: file)
    layout.togglePin(rooms[0])
    layout.move(rooms[1], to: work)
    _ = layout.sections(merging: [], rooms: [])

    let relaunched = RoomLayout(fileURL: file)
    #expect(relaunched.isPinned(rooms[0]))
    #expect(relaunched.section(of: rooms[1]) == work)

    relaunched.clear(rooms[0].id)
    #expect(RoomLayout(fileURL: file).entries.keys.sorted() == [rooms[1].id])

    relaunched.reset()
    #expect(RoomLayout(fileURL: file).entries.isEmpty)
}
