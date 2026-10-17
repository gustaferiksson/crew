import Foundation
import ImageIO
import Observation
import SwiftUI

nonisolated struct BotMeta: Hashable, Sendable {
    var title: String?
    var role: String?
    var description: String?
    var shape: String?
    var color: String?
    var custom: Bool?
    var imageKind: String?
    var expression: String?
    var pinned: Bool?
    var hidden: Bool?
    var sectionID: String?
    var sectionName: String?
    var extra: [String: JSONValue] = [:]
}

nonisolated extension BotMeta: Codable {
    private enum CodingKeys: String, CodingKey {
        case title, role, description, shape, color, custom, imageKind, expression, pinned, hidden, sectionName
        case sectionID = "sectionId"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        role = try? container.decodeIfPresent(String.self, forKey: .role)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        shape = try? container.decodeIfPresent(String.self, forKey: .shape)
        color = try? container.decodeIfPresent(String.self, forKey: .color)
        custom = try? container.decodeIfPresent(Bool.self, forKey: .custom)
        imageKind = try? container.decodeIfPresent(String.self, forKey: .imageKind)
        expression = try? container.decodeIfPresent(String.self, forKey: .expression)
        pinned = try? container.decodeIfPresent(Bool.self, forKey: .pinned)
        hidden = try? container.decodeIfPresent(Bool.self, forKey: .hidden)
        sectionID = try? container.decodeIfPresent(String.self, forKey: .sectionID)
        sectionName = try? container.decodeIfPresent(String.self, forKey: .sectionName)
        extra = try decoder.singleValueContainer().decode([String: JSONValue].self).filter { CodingKeys(stringValue: $0.key) == nil }
    }

    func encode(to encoder: any Encoder) throws {
        var object = extra
        object[CodingKeys.title.stringValue] = title.map(JSONValue.string)
        object[CodingKeys.role.stringValue] = role.map(JSONValue.string)
        object[CodingKeys.description.stringValue] = description.map(JSONValue.string)
        object[CodingKeys.shape.stringValue] = shape.map(JSONValue.string)
        object[CodingKeys.color.stringValue] = color.map(JSONValue.string)
        object[CodingKeys.custom.stringValue] = custom.map(JSONValue.bool)
        object[CodingKeys.imageKind.stringValue] = imageKind.map(JSONValue.string)
        object[CodingKeys.expression.stringValue] = expression.map(JSONValue.string)
        object[CodingKeys.pinned.stringValue] = pinned.map(JSONValue.bool)
        object[CodingKeys.hidden.stringValue] = hidden.map(JSONValue.bool)
        object[CodingKeys.sectionID.stringValue] = sectionID.map(JSONValue.string)
        object[CodingKeys.sectionName.stringValue] = sectionName.map(JSONValue.string)
        try object.encode(to: encoder)
    }
}

nonisolated struct CanonicalSession: Codable, Hashable, Sendable {
    let id: StoredSessionID
    let resolvedID: StoredSessionID
    let preview: String?
    let lastActive: Date?
    let messageCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, preview
        case resolvedID = "resolved_id"
        case lastActive = "last_active"
        case messageCount = "message_count"
    }

    var position: ReadPosition? {
        messageCount.map { ReadPosition(session: resolvedID.rawValue, messages: $0) }
    }
}

nonisolated struct Bot: Identifiable, Hashable, Sendable {
    let name: String
    let displayName: String?
    let description: String?
    let model: String?
    let isDefault: Bool
    let hasAvatar: Bool
    let canonicalSession: CanonicalSession?
    var meta: BotMeta
    var metaRevision: Int?
    var readPosition: ReadPosition?
    var readRevision: Int?

    var id: String { name }

    var lastRead: ReadPosition? {
        readPosition.map { read in canonicalSession?.position.map { min(read, $0) } ?? read }
    }

    func needsMarker(at target: ReadPosition) -> Bool {
        guard target != readPosition, canonicalSession?.position.map({ target <= $0 }) ?? true else { return false }
        return lastRead.map { target >= $0 } ?? true
    }

    var title: String {
        [meta.title, displayName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            ?? (name == "default" ? "Hermes" : name)
    }

    var role: String? {
        let role = (meta.role ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return role.isEmpty ? nil : role
    }
}

nonisolated extension Bot: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, description, model
        case displayName = "display_name"
        case isDefault = "is_default"
        case hasAvatar = "has_avatar"
        case canonicalSession = "canonical_session"
        case uiMeta = "ui_meta"
        case uiMetaRevisions = "ui_meta_revisions"
    }

    private enum Namespace: String, CodingKey {
        case bots = "hermes-bots"
        case crew
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        hasAvatar = try container.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        canonicalSession = try container.decodeIfPresent(CanonicalSession.self, forKey: .canonicalSession)
        meta = try (try? container.nestedContainer(keyedBy: Namespace.self, forKey: .uiMeta))?.decodeIfPresent(BotMeta.self, forKey: .bots) ?? BotMeta()
        metaRevision = try? container.nestedContainer(keyedBy: Namespace.self, forKey: .uiMetaRevisions).decodeIfPresent(Int.self, forKey: .bots)
        readPosition = try? (try? container.nestedContainer(keyedBy: Namespace.self, forKey: .uiMeta))?.decodeIfPresent(ReadPosition.self, forKey: .crew)
        readRevision = try? container.nestedContainer(keyedBy: Namespace.self, forKey: .uiMetaRevisions).decodeIfPresent(Int.self, forKey: .crew)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(hasAvatar, forKey: .hasAvatar)
        try container.encodeIfPresent(canonicalSession, forKey: .canonicalSession)
        var uiMeta = container.nestedContainer(keyedBy: Namespace.self, forKey: .uiMeta)
        try uiMeta.encode(meta, forKey: .bots)
        try uiMeta.encodeIfPresent(readPosition, forKey: .crew)
        var revisions = container.nestedContainer(keyedBy: Namespace.self, forKey: .uiMetaRevisions)
        try revisions.encodeIfPresent(metaRevision, forKey: .bots)
        try revisions.encodeIfPresent(readRevision, forKey: .crew)
    }
}

nonisolated struct ReadPosition: Codable, Hashable, Comparable, Sendable {
    let session: String
    let messages: Int

    static func < (lhs: ReadPosition, rhs: ReadPosition) -> Bool {
        (lhs.session, lhs.messages) < (rhs.session, rhs.messages)
    }
}

nonisolated enum WaitingKind: String, Sendable {
    case approval, question, payment

    init(_ request: ServerRequest) {
        if PendingRequest(request)?.isPayment == true {
            self = .payment
        } else {
            self = request.method == "approval" ? .approval : .question
        }
    }
}

nonisolated enum BotStatus: Hashable, Sendable {
    case idle
    case unread
    case working
    case waiting(WaitingKind?)
    case failed

    init?(live status: String, waiting kind: WaitingKind?) {
        if status == "waiting" {
            self = .waiting(kind)
            return
        }
        guard status == "working" else { return nil }
        self = .working
    }
}

nonisolated struct SectionTag: Hashable, Sendable {
    let id: String
    let name: String
}

nonisolated struct NewProfile: Encodable, Sendable {
    let name: String
    let description: String?
    let soul: String?
    let cloneFrom: String?

    private enum CodingKeys: String, CodingKey {
        case name, description, soul
        case cloneFrom = "clone_from"
    }
}

struct BotSection: Identifiable {
    let id: String
    let name: String?
    let bots: [Bot]
}

nonisolated struct Roster: Decodable {
    let profiles: [Bot]
}

nonisolated struct LiveSession: Decodable {
    let id: RuntimeSessionID
    let sessionKey: StoredSessionID
    let status: String

    private enum CodingKeys: String, CodingKey {
        case id, status
        case sessionKey = "session_key"
    }
}

nonisolated struct ActiveList: Decodable {
    let sessions: [LiveSession]
}

nonisolated private struct ProfileAsset: Decodable {
    let found: Bool
    let data: String?
}

nonisolated private struct ConfigureMeta<Meta: Encodable & Sendable>: Encodable, Sendable {
    let name: String
    let uiMeta: [String: Meta]
    let uiMetaExpectedRevisions: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case name
        case uiMeta = "ui_meta"
        case uiMetaExpectedRevisions = "ui_meta_expected_revisions"
    }
}

@Observable
final class BotStore {
    private(set) var bots: [Bot]
    private(set) var statuses: [Bot.ID: BotStatus]
    private(set) var isLoaded: Bool
    private(set) var photos: [Bot.ID: Image]
    private(set) var previews: [Bot.ID: LastMessage] = [:]
    var isForeground = true

    private let cacheURL: URL?
    private let photoDirectory: URL?
    private var photoRevisions: [Bot.ID: Int] = [:]
    private var previewPositions: [Bot.ID: ReadPosition] = [:]
    private var liveSessions: [LiveSession] = []
    private var waitingKinds: [RuntimeSessionID: WaitingKind] = [:]
    private var seenActivity: [Bot.ID: ReadPosition] = [:]
    private var firstSeenActivity: [Bot.ID: ReadPosition] = [:]
    private var readWrites: [Bot.ID: Task<Void, Never>] = [:]
    private var clearingUnread: Set<Bot.ID> = []
    let unreadCleared = AsyncStream.makeStream(of: Bot.self)
    private var gateway: Gateway?
    private var urlSession: URLSession?
    private var reloadTask: Task<Void, Never>?

    init() {
        let cacheURL = URL.applicationSupportDirectory.appending(path: "bots.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? decoder.decode([Bot].self, from: $0) }
        let photoDirectory = URL.cachesDirectory.appending(path: "avatars")
        self.cacheURL = cacheURL
        self.photoDirectory = photoDirectory
        self.bots = cached ?? []
        self.statuses = [:]
        self.isLoaded = cached != nil
        self.photos = Dictionary(uniqueKeysWithValues: (cached ?? []).compactMap { bot in
            (try? Data(contentsOf: photoDirectory.appending(path: bot.id))).flatMap(Self.photo).map { (bot.id, $0) }
        })
    }

    init(fixture bots: [Bot], statuses: [Bot.ID: BotStatus], photos: [Bot.ID: Image] = [:]) {
        self.cacheURL = nil
        self.photoDirectory = nil
        self.bots = bots
        self.statuses = statuses
        self.isLoaded = true
        self.photos = photos
    }

    var favourites: [Bot] {
        ranked.filter { $0.meta.pinned == true }
    }

    var sections: [BotSection] {
        let listed = ranked.filter { $0.meta.pinned != true }
        let isFiled = { (bot: Bot) in bot.meta.sectionID?.isEmpty == false && bot.meta.sectionName?.isEmpty == false }
        let filed = Dictionary(grouping: listed.filter(isFiled)) { $0.meta.sectionID ?? "" }
        let named = filed
            .map { BotSection(id: $0.key, name: $0.value.first?.meta.sectionName, bots: $0.value) }
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
        let unfiled = listed.filter { !isFiled($0) }
        guard !unfiled.isEmpty else { return named }
        return named + [BotSection(id: "", name: named.isEmpty ? nil : String(localized: "Other"), bots: unfiled)]
    }

    private var ranked: [Bot] {
        let rank = { (bot: Bot) -> Int in
            let status = self.statuses[bot.id] ?? .idle
            if case .waiting = status { return 3 }
            if status == .working { return 2 }
            return status == .unread ? 1 : 0
        }
        return bots
            .filter { $0.meta.hidden != true }
            .sorted { lhs, rhs in
                guard rank(lhs) == rank(rhs) else { return rank(lhs) > rank(rhs) }
                return (lhs.canonicalSession?.lastActive ?? .distantPast) > (rhs.canonicalSession?.lastActive ?? .distantPast)
            }
    }

    func run(_ gateway: Gateway, urlSession: URLSession) async {
        self.gateway = gateway
        self.urlSession = urlSession
        let events = gateway.events()
        let requests = gateway.serverRequests()
        if await gateway.status == .connected { await reload(gateway) }
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await event in events where ["gateway.ready", "sessions.changed"].contains(event.type) {
                    await self.scheduleReload(gateway)
                }
            }
            group.addTask {
                for await request in requests {
                    await self.note(request, gateway: gateway)
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    await self.refresh(gateway)
                }
            }
        }
    }

    func markSeen(_ bot: Bot) {
        guard let position = bot.canonicalSession?.position else { return }
        let read = [bots.first { $0.id == bot.id }?.lastRead, seenActivity[bot.id], firstSeenActivity[bot.id]].compactMap(\.self).max()
        if let read, position <= read { return }
        if statuses[bot.id] == .unread { clearingUnread.insert(bot.id) }
        seenActivity[bot.id] = position
        updateStatuses()
        sendReadMarkers()
    }

    private func sendReadMarkers() {
        for id in seenActivity.keys where readWrites[id] == nil {
            readWrites[id] = Task {
                while await writeReadMarker(of: id) {
                    try? await Task.sleep(for: .seconds(2))
                }
                readWrites[id] = nil
            }
        }
    }

    private func writeReadMarker(of id: Bot.ID) async -> Bool {
        for _ in 0..<3 {
            guard let gateway, let target = seenActivity[id], let bot = bots.first(where: { $0.id == id }) else { return false }
            guard bot.needsMarker(at: target) else { return false }
            let params = ConfigureMeta(name: bot.name, uiMeta: ["crew": target], uiMetaExpectedRevisions: ["crew": bot.readRevision ?? 0])
            guard let applied = try? await gateway.call("profiles.configure", params, as: ConfigureReply.self).applied else { return false }
            if applied.uiMeta == true, let revision = applied.uiMetaRevisions?["crew"] {
                guard let index = bots.firstIndex(where: { $0.id == id }) else { return false }
                bots[index].readPosition = target
                bots[index].readRevision = revision
                saveCache()
                if clearingUnread.remove(id) != nil { unreadCleared.continuation.yield(bots[index]) }
                return true
            }
            guard applied.uiMetaConflicts != nil else { return false }
            await reload(gateway)
        }
        return false
    }

    var sectionTags: [SectionTag] {
        Set(bots.compactMap { bot in
            guard let id = bot.meta.sectionID, let name = bot.meta.sectionName, !id.isEmpty, !name.isEmpty else { return nil }
            return SectionTag(id: id, name: name)
        })
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func togglePin(_ bot: Bot, via gateway: Gateway) async throws {
        let pinned = bot.meta.pinned != true
        try await updateMeta(of: bot.name, via: gateway) { $0.pinned = pinned }
    }

    func move(_ bot: Bot, to section: SectionTag?, via gateway: Gateway) async throws {
        try await updateMeta(of: bot.name, via: gateway) { meta in
            meta.sectionID = section?.id
            meta.sectionName = section?.name
        }
    }

    func create(_ profile: NewProfile, via gateway: Gateway, look: (inout BotMeta) -> Void) async throws {
        _ = try await gateway.call("profiles.create", profile, as: JSONValue.self)
        await reload(gateway)
        try await updateMeta(of: profile.name, via: gateway) { meta in
            look(&meta)
            meta.extra["created"] = .number((Date.now.timeIntervalSince1970 * 1000).rounded())
        }
        await reload(gateway)
    }

    func duplicate(_ bot: Bot, via gateway: Gateway) async throws -> Bot.ID {
        let taken = Set(bots.map(\.name))
        let candidates = (2..<100).lazy.map { "\(bot.name.prefix(64 - "-\($0)".count))-\($0)" }
        guard let name = candidates.first(where: { !taken.contains($0) }) else {
            throw GatewayError.rpc(code: 0, message: String(localized: "There's no free name for a copy of \(bot.title)."))
        }
        let photo = bot.hasAvatar ? try? await gateway.call("profiles.get_asset", ["name": bot.name, "asset": "avatar"], as: ProfileAsset.self).data : nil
        try await create(NewProfile(name: name, description: bot.description, soul: nil, cloneFrom: bot.name), via: gateway) { meta in
            meta = bot.meta
            meta.title = String(localized: "\(bot.title) (copy)")
            meta.pinned = nil
            meta.hidden = nil
            if photo == nil && meta.imageKind == "photo" { meta.imageKind = nil }
        }
        if let photo {
            _ = try? await gateway.call("profiles.set_asset", AssetChange(name: name, data: photo, clear: nil), as: AssetReply.self)
            await reload(gateway)
        }
        return name
    }

    func delete(_ bot: Bot, via gateway: Gateway, urlSession: URLSession) async throws {
        guard !bot.isDefault, bot.name != "default" else {
            throw GatewayError.rpc(code: 0, message: String(localized: "The default bot can't be deleted."))
        }
        var request = hermesRequest("api/profiles/\(bot.name)", on: gateway.server)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 45
        _ = try await fetch(request, with: urlSession, as: JSONValue.self)
        bots.removeAll { $0.id == bot.id }
        saveCache()
        updateStatuses()
        await reload(gateway)
    }

    private func updateMeta(of name: String, via gateway: Gateway, _ change: (inout BotMeta) -> Void) async throws {
        for _ in 0..<3 {
            let current = bots.first { $0.name == name }
            var meta = current?.meta ?? BotMeta()
            change(&meta)
            let params = ConfigureMeta(name: name, uiMeta: ["hermes-bots": meta], uiMetaExpectedRevisions: ["hermes-bots": current?.metaRevision ?? 0])
            let applied = try await gateway.call("profiles.configure", params, as: ConfigureReply.self).applied
            if applied.uiMeta == true, let revision = applied.uiMetaRevisions?["hermes-bots"] {
                guard let index = bots.firstIndex(where: { $0.name == name }) else { return }
                if photoRevisions[name] == bots[index].metaRevision ?? 0 { photoRevisions[name] = revision }
                bots[index].meta = meta
                bots[index].metaRevision = revision
                saveCache()
                return
            }
            guard applied.uiMetaConflicts != nil else { throw GatewayError.rpc(code: 0, message: String(localized: "The server didn't save the change.")) }
            await reload(gateway)
        }
        throw GatewayError.rpc(code: 0, message: String(localized: "Another device keeps changing this bot."))
    }

    func reset() {
        reloadTask?.cancel()
        bots = []
        statuses = [:]
        photos = [:]
        photoRevisions = [:]
        previews = [:]
        previewPositions = [:]
        liveSessions = []
        waitingKinds = [:]
        for write in readWrites.values { write.cancel() }
        readWrites = [:]
        clearingUnread = []
        seenActivity = [:]
        firstSeenActivity = [:]
        gateway = nil
        urlSession = nil
        isLoaded = false
        guard let cacheURL, let photoDirectory else { return }
        try? FileManager.default.removeItem(at: cacheURL)
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    private func scheduleReload(_ gateway: Gateway) {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await reload(gateway)
        }
    }

    func reload(_ gateway: Gateway) async {
        guard let roster = try? await gateway.call("profiles.list", ["include_sessions": true], as: Roster.self) else { return }
        apply(roster: roster.profiles)
        await poll(gateway)
        await refreshPhotos(gateway)
        await refreshPreviews(gateway)
    }

    func apply(roster: [Bot]) {
        if !isLoaded { isLoaded = true }
        if roster != bots {
            bots = roster
            saveCache()
        }
        seenActivity = seenActivity.filter { seen in bots.contains { $0.id == seen.key && $0.needsMarker(at: seen.value) } }
        clearingUnread = clearingUnread.filter { seenActivity[$0] != nil }
        for bot in bots where bot.lastRead != bot.readPosition && seenActivity[bot.id] == nil {
            seenActivity[bot.id] = bot.lastRead
        }
        firstSeenActivity = firstSeenActivity.filter { seen in bots.contains { $0.id == seen.key && $0.readPosition == nil } }
        for bot in bots {
            guard let seen = firstSeenActivity[bot.id], let position = bot.canonicalSession?.position else { continue }
            firstSeenActivity[bot.id] = min(seen, position)
        }
        for bot in bots where bot.readPosition == nil && seenActivity[bot.id] == nil && firstSeenActivity[bot.id] == nil {
            firstSeenActivity[bot.id] = bot.canonicalSession?.position
        }
        sendReadMarkers()
    }

    private func saveCache() {
        guard let cacheURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(bots).write(to: cacheURL, options: .atomic)
    }

    private func refreshPhotos(_ gateway: Gateway) async {
        guard let photoDirectory else { return }
        let wanted = bots.filter { $0.hasAvatar && $0.meta.imageKind != "shape" }
        for id in photos.keys where !wanted.contains(where: { $0.id == id }) {
            photos[id] = nil
            photoRevisions[id] = nil
            try? FileManager.default.removeItem(at: photoDirectory.appending(path: id))
        }
        for bot in wanted where photoRevisions[bot.id] != bot.metaRevision ?? 0 {
            guard let asset = try? await gateway.call("profiles.get_asset", ["name": bot.name, "asset": "avatar"], as: ProfileAsset.self) else { return }
            let file = photoDirectory.appending(path: bot.id)
            let encoded = asset.data.flatMap { $0.hasPrefix("data:image/") ? $0.split(separator: ",", maxSplits: 1).last : nil }
            let data = encoded.flatMap { Data(base64Encoded: String($0)) }
            photoRevisions[bot.id] = bot.metaRevision ?? 0
            guard asset.found, let data, let photo = Self.photo(from: data) else {
                photos[bot.id] = nil
                try? FileManager.default.removeItem(at: file)
                continue
            }
            photos[bot.id] = photo
            try? FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    private func refreshPreviews(_ gateway: Gateway) async {
        guard let urlSession else { return }
        for bot in bots {
            guard let session = bot.canonicalSession, let position = session.position, previewPositions[bot.id] != position else { continue }
            previewPositions[bot.id] = position
            guard let rows = try? await history(of: session.resolvedID, profile: bot.name, on: gateway.server, with: urlSession, limit: 20) else {
                previewPositions[bot.id] = nil
                continue
            }
            showPreview(of: bot.id, from: rows)
        }
    }

    func showPreview(of id: Bot.ID, from rows: [HistoryRow]) {
        previews[id] = Transcript(history: Array(rows.sorted { $0.id < $1.id }.drop { $0.role != "user" })).preview
    }

    private static func photo(from data: Data) -> Image? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return Image(decorative: image, scale: 1)
    }

    private func refresh(_ gateway: Gateway) async {
        guard await gateway.status == .connected else { return }
        if isForeground { return await reload(gateway) }
        guard statuses.values.contains(where: { $0 != .unread }) else { return }
        await poll(gateway)
    }

    private func poll(_ gateway: Gateway) async {
        guard let list = try? await gateway.call("session.active_list", [String: String](), as: ActiveList.self) else { return }
        let wasBusy = statuses.values.contains { $0 != .unread }
        apply(live: list.sessions)
        if wasBusy && !statuses.values.contains(where: { $0 != .unread }) { scheduleReload(gateway) }
    }

    func apply(live sessions: [LiveSession]) {
        liveSessions = sessions
        waitingKinds = waitingKinds.filter { kind in sessions.contains { $0.id == kind.key && $0.status == "waiting" } }
        updateStatuses()
    }

    private func note(_ request: ServerRequest, gateway: Gateway) async {
        guard let session = request.sessionID else { return }
        waitingKinds[session] = WaitingKind(request)
        await poll(gateway)
    }

    private func updateStatuses() {
        var owners: [StoredSessionID: Set<Bot.ID>] = [:]
        for bot in bots {
            guard let session = bot.canonicalSession else { continue }
            owners[session.id, default: []].insert(bot.id)
            owners[session.resolvedID, default: []].insert(bot.id)
        }
        var result: [Bot.ID: BotStatus] = [:]
        for bot in bots {
            guard let position = bot.canonicalSession?.position, let read = [bot.lastRead, seenActivity[bot.id], firstSeenActivity[bot.id]].compactMap(\.self).max(), position > read else { continue }
            result[bot.id] = .unread
        }
        for session in liveSessions.sorted(by: { $1.status == "waiting" && $0.status != "waiting" }) {
            guard let matched = owners[session.sessionKey], matched.count == 1, let id = matched.first, let status = BotStatus(live: session.status, waiting: waitingKinds[session.id]) else { continue }
            result[id] = status
        }
        if statuses != result { statuses = result }
    }
}
