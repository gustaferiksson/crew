import Foundation

struct PokeTracker: Equatable {
    private(set) var count = 0
    private(set) var isGrumpy = false
    private var recent: [Date] = []

    mutating func poke(at now: Date) {
        let window = recent.filter { now.timeIntervalSince($0) < 2 } + [now]
        isGrumpy = window.count >= 3
        recent = isGrumpy ? [] : window
        count += 1
    }
}
