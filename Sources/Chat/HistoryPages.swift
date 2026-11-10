import Foundation

enum EarlierHistory {
    case complete, more, loading, failed
}

struct HistoryPages {
    let size: Int
    private(set) var rows: [HistoryRow] = []
    private(set) var reachedStart = false

    init(size: Int = BotStore.pageRows) {
        self.size = size
    }

    var transcript: Transcript {
        reachedStart ? Transcript(history: rows) : Transcript(window: rows)
    }

    mutating func merge(latest page: [HistoryRow]) {
        let page = page.sorted { $0.id < $1.id }
        guard page.count == size, let first = page.first, let newest = rows.last, first.id <= newest.id else {
            rows = page
            reachedStart = page.count < size
            return
        }
        rows = rows.filter { $0.id < first.id } + page
    }

    mutating func prepend(older page: [HistoryRow]) {
        let oldest = rows.first?.id ?? .max
        rows = page.filter { $0.id < oldest }.sorted { $0.id < $1.id } + rows
        reachedStart = page.count < size
    }
}
