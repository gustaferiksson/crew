import A2UICore
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
        case surfaces([String])
        case failed(String)
    }

    private(set) var blocks: [String: Block] = [:]
    private(set) var owners: [String: String] = [:]
    private(set) var choices: [String: String] = [:]
    private(set) var isBusy = false
    private(set) var newest: ChatPins.Card?
    private(set) var present: Set<String> = []
    @ObservationIgnored var send: (String) -> Void = { _ in }
    @ObservationIgnored let processor = MessageProcessor(catalogs: crewCatalogs)
    @ObservationIgnored private var replyBlocks: [String: [String]] = [:]

    init() {
        processor.outboundListener = { [weak self] message in
            MainActor.assumeIsolated { self?.forward(message) }
        }
    }

    func sync(_ transcript: Transcript) {
        var choices: [String: String] = [:]
        var cards: [ChatPins.Card] = []
        for turn in transcript.turns {
            if let action = turn.hiddenText.flatMap(SentAction.init(text:)) {
                choices[action.surfaceId] = action.sourceComponentId
            }
            guard turn.status != .streaming, turn.reply.contains("a2ui") else { continue }
            for source in replyBlocks[turn.reply] ?? read(turn.reply) {
                guard case .surfaces(let ids) = blocks[source] else { continue }
                cards += ids.map { ChatPins.Card(surface: $0, source: source, finishedAt: turn.finishedAt ?? turn.startedAt) }
            }
        }
        if choices != self.choices { self.choices = choices }
        if cards.last != newest { newest = cards.last }
        let present = Set(cards.map(\.surface))
        if present != self.present { self.present = present }
        let isBusy = transcript.turns.last?.status == .streaming
        if isBusy != self.isBusy { self.isBusy = isBusy }
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
        let created = (payload.arrayValue ?? [payload]).compactMap { $0["createSurface"]?["surfaceId"]?.stringValue }
        do {
            for id in created where processor.surfaceGroupModel[id] != nil {
                try processor.processMessages(["version": "v0.9", "deleteSurface": ["surfaceId": .string(id)]])
            }
            try processor.processMessages(payload)
        } catch {
            return .failed(String(describing: error))
        }
        for id in created { owners[id] = source }
        return .surfaces(created)
    }

    private func forward(_ message: RendererToAgentMessage) {
        guard case .action(let action) = message else { return }
        let sent = SentAction(name: action.name, surfaceId: action.surfaceID, sourceComponentId: action.sourceComponentID, context: action.context)
        guard let json = try? sentActionEncoder.encode(sent) else { return }
        send("<a2ui-action>\(String(decoding: json, as: UTF8.self))</a2ui-action>")
    }
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
