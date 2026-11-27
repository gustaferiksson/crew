import Foundation

nonisolated struct TranscriptRow: Identifiable {
    let turns: [Turn]

    var id: String { turns.count > 1 ? "\(turns[0].id)-group" : turns[0].id }
}

nonisolated extension Turn {
    var isBotExchange: Bool {
        agentMessage != nil && pending == nil && notice == nil && warnings.isEmpty && deliveryFailure == nil && status != .error && status != .interrupted
    }
}

nonisolated extension Transcript {
    var rows: [TranscriptRow] {
        turns.reduce(into: [[Turn]]()) { chunks, turn in
            if turn.isBotExchange, chunks.last?.last?.isBotExchange == true {
                chunks[chunks.count - 1].append(turn)
            } else {
                chunks.append([turn])
            }
        }
        .map(TranscriptRow.init)
    }
}
