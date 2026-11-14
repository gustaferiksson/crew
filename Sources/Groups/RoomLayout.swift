import Foundation
import Observation

@Observable
final class RoomLayout {
    static let shared = RoomLayout()

    struct Entry: Codable, Equatable {
        var pinned = false
        var section: SectionTag?
    }

    private(set) var entries: [String: Entry]
    private let fileURL: URL?

    init(fileURL: URL? = URL.applicationSupportDirectory.appending(path: "room-layout.json")) {
        self.fileURL = fileURL
        entries = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    init(fixture entries: [String: Entry]) {
        fileURL = nil
        self.entries = entries
    }

    func isPinned(_ room: Room) -> Bool {
        entries[room.id]?.pinned == true
    }

    func section(of room: Room) -> SectionTag? {
        entries[room.id]?.section
    }

    func pinned(_ rooms: [Room]) -> [Room] {
        rooms.filter(isPinned).sorted { $0.updatedAt > $1.updatedAt }
    }

    func togglePin(_ room: Room) {
        update(room.id) { $0.pinned.toggle() }
    }

    func move(_ room: Room, to section: SectionTag?) {
        update(room.id) { $0.section = section }
    }

    func clear(_ roomID: String) {
        guard entries[roomID] != nil else { return }
        entries[roomID] = nil
        save()
    }

    func reset() {
        entries = [:]
        save()
    }

    func sectionTags(merging botTags: [SectionTag], rooms: [Room]) -> [SectionTag] {
        let botIDs = Set(botTags.map(\.id))
        let roomTags = Dictionary(rooms.compactMap(section(of:)).filter { !botIDs.contains($0.id) }.map { ($0.id, $0) }) { first, _ in first }.values
        return (botTags + roomTags).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func sections(merging botSections: [BotSection], rooms: [Room]) -> [BotSection] {
        let botIDs = Set(botSections.map(\.id))
        let roomOnly = Dictionary(rooms.filter { !isPinned($0) }.compactMap(section(of:)).filter { !botIDs.contains($0.id) }.map { ($0.id, $0) }) { first, _ in first }
            .values.map { BotSection(id: $0.id, name: $0.name, bots: []) }
        let named = (botSections.filter { !$0.id.isEmpty } + roomOnly)
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
        let unfiled = botSections.first { $0.id.isEmpty }
        let hasUnfiledRooms = rooms.contains { !isPinned($0) && section(of: $0) == nil }
        guard unfiled != nil || hasUnfiledRooms else { return named }
        return named + [BotSection(id: "", name: named.isEmpty ? nil : String(localized: "Other"), bots: unfiled?.bots ?? [])]
    }

    func rooms(in section: BotSection, of rooms: [Room]) -> [Room] {
        rooms.filter { !isPinned($0) && (self.section(of: $0)?.id ?? "") == section.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func update(_ roomID: String, _ change: (inout Entry) -> Void) {
        var entry = entries[roomID] ?? Entry()
        change(&entry)
        entries[roomID] = entry == Entry() ? nil : entry
        save()
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
