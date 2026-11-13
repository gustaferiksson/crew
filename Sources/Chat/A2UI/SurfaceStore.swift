import A2UICore
import Combine
import CryptoKit
import Foundation
import Observation
import OrderedJSON
import SwiftUI

private let blockLimit = 64 * 1024

extension EnvironmentValues {
    @Entry var surfaces: SurfaceStore?
}

@Observable
final class SurfaceStore {
    enum Block: Equatable {
        case surfaces(created: [String], revised: [String], updated: [String])
        case lost
        case failed(String)
    }

    private(set) var blocks: [String: Block] = [:]
    private(set) var owners: [String: String] = [:]
    private(set) var choices: [String: String] = [:]
    private(set) var isBusy = false
    private(set) var newest: ChatPins.Card?
    private(set) var present: Set<String> = []
    private(set) var cardTurns: [String: Turn.ID] = [:]
    @ObservationIgnored var send: (String) -> Void = { _ in }
    @ObservationIgnored var saved: (state: CardState, chat: String)?
    @ObservationIgnored private(set) lazy var processor = {
        let processor = MessageProcessor(catalogs: crewCatalogs)
        processor.outboundListener = { [weak self] message in
            MainActor.assumeIsolated { self?.forward(message) }
        }
        return processor
    }()
    @ObservationIgnored private var replyBlocks: [String: [String]] = [:]
    @ObservationIgnored private var previews: [String: (healed: String, processor: MessageProcessor)] = [:]
    @ObservationIgnored private var fingerprints: [String: String] = [:]
    @ObservationIgnored private var updateHashes: [String: [String]] = [:]
    @ObservationIgnored private var lastData: [String: OrderedJSON.JSONValue] = [:]
    @ObservationIgnored private var watches: [String: AnyCancellable] = [:]
    @ObservationIgnored private var isApplying = false

    func sync(_ transcript: Transcript) {
        var choices: [String: String] = [:]
        var cards: [ChatPins.Card] = []
        var cardTurns: [String: Turn.ID] = [:]
        for turn in transcript.turns {
            if let action = turn.hiddenText.flatMap(SentAction.init(text:)) {
                choices[action.surfaceId] = action.sourceComponentId
            }
            guard turn.status != .streaming, turn.reply.contains("a2ui") else { continue }
            for source in replyBlocks[turn.reply] ?? read(turn.reply) {
                guard case .surfaces(let ids, _, _) = blocks[source] else { continue }
                cards += ids.map { ChatPins.Card(surface: $0, source: source, finishedAt: turn.finishedAt ?? turn.startedAt) }
                for id in ids where owners[id] == source {
                    cardTurns[id] = turn.id
                }
            }
        }
        if choices != self.choices { self.choices = choices }
        if cardTurns != self.cardTurns { self.cardTurns = cardTurns }
        if cards.last != newest { newest = cards.last }
        let present = Set(cards.map(\.surface))
        if present != self.present { self.present = present }
        let isBusy = transcript.turns.last?.status == .streaming
        if isBusy != self.isBusy { self.isBusy = isBusy }
        if !isBusy { previews.removeAll() }
        restore()
    }

    func preview(_ partial: String) -> SurfaceViewModel? {
        guard partial.utf8.count <= blockLimit, let healed = healedA2UIPrefix(partial),
              let id = healed.firstMatch(of: /"createSurface"\s*:\s*\{\s*"surfaceId"\s*:\s*"([^"]+)"/).map({ String($0.1) })
        else { return nil }
        if let previewed = previews[id], previewed.healed == healed { return previewed.processor.surfaceGroupModel[id] }
        guard let payload = try? JSONDecoder().decode(OrderedJSON.JSONValue.self, from: Data(healed.utf8)) else { return nil }
        let processor = MessageProcessor(catalogs: crewCatalogs)
        guard (try? processor.processMessages(payload)) != nil, let model = processor.surfaceGroupModel[id] else { return nil }
        previews[id] = (healed, processor)
        return model
    }

    private func read(_ reply: String) -> [String] {
        let sources = markdownBlocks(from: a2uiFenced(reply))
            .filter { $0.kind == .code(language: "a2ui") }
            .map { String($0.content.characters).trimmingCharacters(in: .newlines) }
        for source in sources where blocks[source] == nil {
            blocks[source] = ingest(source)
        }
        replyBlocks[reply] = sources
        return sources
    }

    private func ingest(_ source: String) -> Block {
        guard source.utf8.count <= blockLimit else { return .failed(String(localized: "It's larger than 64 KB.")) }
        guard let payload = try? JSONDecoder().decode(OrderedJSON.JSONValue.self, from: Data(source.utf8)) else {
            return .failed(String(localized: "It isn't valid JSON."))
        }
        let messages = payload.arrayValue ?? [payload]
        let created = messages.compactMap { $0["createSurface"]?["surfaceId"]?.stringValue }
        let updated = messages.compactMap { ($0["updateComponents"] ?? $0["updateDataModel"])?["surfaceId"]?.stringValue }
            .filter { !created.contains($0) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if created.isEmpty, !updated.isEmpty, updated.allSatisfy({ processor.surfaceGroupModel[$0] == nil }) { return .lost }
        let revised = created.filter { processor.surfaceGroupModel[$0] != nil }
        let hash = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let botPaths = messages.compactMap { message in
            message["updateDataModel"].flatMap { update in update["surfaceId"]?.stringValue.map { (surface: $0, path: update["path"]?.stringValue ?? "/") } }
        }
        for id in updated where botPaths.contains(where: { $0.surface == id }) {
            updateHashes[id, default: []].append(hash)
            guard let saved, let fingerprint = fingerprints[id] else { continue }
            saved.state.botUpdated(botPaths.filter { $0.surface == id }.map(\.path), with: hash, on: fingerprint, in: saved.chat)
        }

        isApplying = true
        defer { isApplying = false }
        do {
            for id in revised {
                try processor.processMessages(["version": "v0.9", "deleteSurface": ["surfaceId": .string(id)]])
            }
            try processor.processMessages(payload)
        } catch {
            return .failed(String(describing: error))
        }
        for id in created {
            owners[id] = source
            fingerprints[id] = id + ":" + hash
            updateHashes[id] = []
            watch(id)
        }
        return .surfaces(created: created, revised: revised, updated: updated)
    }

    private func watch(_ id: String) {
        guard let data = processor.surfaceGroupModel[id]?.dataModel else { return }
        lastData[id] = data.data
        watches[id] = data.dataPublisher.sink { [weak self] new in
            self?.dataChanged(id, to: new)
        }
    }

    private func dataChanged(_ id: String, to new: OrderedJSON.JSONValue) {
        let old = lastData[id]
        lastData[id] = new
        guard !isApplying, let saved, let fingerprint = fingerprints[id] else { return }

        let changes = changedLeaves(from: old, to: new, at: "")
        guard !changes.isEmpty else { return }
        saved.state.userChanged(changes, on: fingerprint, after: updateHashes[id] ?? [], in: saved.chat)
    }

    private func restore() {
        guard let saved else { return }
        isApplying = true
        defer { isApplying = false }

        for (id, fingerprint) in fingerprints {
            guard let data = processor.surfaceGroupModel[id]?.dataModel else { continue }
            for (path, value) in saved.state.values(of: fingerprint, in: saved.chat) where data.get(path) != value {
                data.set(path, value: value)
            }
        }
    }

    private func forward(_ message: RendererToAgentMessage) {
        guard case .action(let action) = message else { return }
        let sent = SentAction(name: action.name, surfaceId: action.surfaceID, sourceComponentId: action.sourceComponentID, context: action.context)
        guard let json = try? sentActionEncoder.encode(sent) else { return }
        send("<a2ui-action>\(String(decoding: json, as: UTF8.self))</a2ui-action>")
    }
}

nonisolated private func changedLeaves(from old: OrderedJSON.JSONValue?, to new: OrderedJSON.JSONValue?, at path: String) -> [String: OrderedJSON.JSONValue] {
    if old == new { return [:] }
    if case .object(let before)? = old, case .object(let after)? = new {
        return Set(before.keys).union(after.keys).reduce(into: [:]) { changes, key in
            let escaped = key.replacing("~", with: "~0").replacing("/", with: "~1")
            changes.merge(changedLeaves(from: before[key], to: after[key], at: path + "/" + escaped)) { $1 }
        }
    }
    if case .array(let before)? = old, case .array(let after)? = new, before.count == after.count {
        return before.indices.reduce(into: [:]) { changes, index in
            changes.merge(changedLeaves(from: before[index], to: after[index], at: "\(path)/\(index)")) { $1 }
        }
    }
    return [path: new ?? .null]
}

nonisolated private let sentActionEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

nonisolated private struct SentAction: Codable {
    let name: String
    let surfaceId: String
    let sourceComponentId: String
    let context: [String: OrderedJSON.JSONValue]

    init(name: String, surfaceId: String, sourceComponentId: String, context: [String: OrderedJSON.JSONValue]) {
        self.name = name
        self.surfaceId = surfaceId
        self.sourceComponentId = sourceComponentId
        self.context = context
    }

    init?(text: String) {
        guard let json = text.firstMatch(of: /<a2ui-action>([\s\S]*)<\/a2ui-action>/)?.1,
              let action = try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
        else { return nil }
        self = action
    }
}
