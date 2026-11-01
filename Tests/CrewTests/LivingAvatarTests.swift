import AppKit
import SwiftUI
import Synchronization
import Testing

private let now = Date(timeIntervalSince1970: 1_792_136_000)

private func cycles(_ mood: AvatarMood, seed: String = "ada", count: Int = 200) -> [[EyeStep]] {
    var generator = SeededGenerator(seed: seed)
    return (0..<count).map { _ in mood.cycle(using: &generator) }
}

private func seconds(_ steps: [EyeStep]) -> Double {
    steps.reduce(0) { $0 + Double($1.hold.components.seconds) + Double($1.hold.components.attoseconds) / 1e18 }
}

@Test func statusMapsToMood() {
    let lastWeek = now.addingTimeInterval(-8 * 24 * 3600)
    #expect(AvatarMood(status: .idle, lastActive: now, now: now) == .idle)
    #expect(AvatarMood(status: .idle, lastActive: nil, now: now) == .idle)
    #expect(AvatarMood(status: .idle, lastActive: lastWeek, now: now) == .dormant)
    #expect(AvatarMood(status: .unread, lastActive: lastWeek, now: now) == .unread)
    #expect(AvatarMood(status: .working, lastActive: lastWeek, now: now) == .working)
    #expect(AvatarMood(status: .waiting(.approval), lastActive: now, now: now) == .waiting)
    #expect(AvatarMood(status: .failed, lastActive: now, now: now) == .failed)
}

@Test func restingPosesShowTheState() {
    #expect(AvatarMood.idle.restingPose == .rest)
    #expect(AvatarMood.unread.restingPose == .rest)
    #expect(AvatarMood.working.restingPose == .rest)
    #expect(AvatarMood.waiting.restingPose == .wide)
    #expect(AvatarMood.failed.restingPose == .rest)
    #expect(AvatarMood.dormant.restingPose == .sleepy)
    #expect(EyePose.wide.scale > 1)
    #expect(EyePose.sleepy.openness == 0.5)
}

@Test func idleBlinksAtIrregularSeededIntervalsOfSeveralSeconds() {
    let waits = cycles(.idle).map { Double($0[0].hold.components.seconds) + Double($0[0].hold.components.attoseconds) / 1e18 }
    #expect(waits.allSatisfy { (3...8).contains($0) })
    #expect(Set(waits.map { ($0 * 10).rounded() }).count > 20)
    #expect(cycles(.idle).allSatisfy { $0.contains { $0.pose == EyePose.rest.blinked } })
    #expect(cycles(.idle).contains { $0.count == 5 })
    #expect(cycles(.idle) == cycles(.idle))
    #expect(cycles(.idle, seed: "ada") != cycles(.idle, seed: "grace"))
}

@Test func idleChangesTheEyesOnlyAFewTimesAMinute() {
    let all = cycles(.idle)
    let changes = all.reduce(0) { $0 + $1.count - 1 }
    let perMinute = Double(changes) / seconds(all.flatMap { $0 }) * 60
    #expect(perMinute < 30, "\(perMinute)")
}

@Test func workingReadsAlongLinesAndPausesBetween() {
    for cycle in cycles(.working) {
        let gazes = cycle.map(\.pose.gaze.width)
        #expect(gazes.contains(EyePose.readingStart.gaze.width))
        #expect(gazes.contains(EyePose.readingEnd.gaze.width))
        #expect(cycle[0].pose == .rest && seconds([cycle[0]]) >= 2)
        #expect(cycle.allSatisfy { $0.pose.scale == 1 })
    }
    let all = cycles(.working).flatMap { $0 }
    #expect(Double(all.count) / seconds(all) * 60 < 90)
}

@Test func waitingHoldsWideAndBlinksFromThere() {
    for cycle in cycles(.waiting) {
        #expect(cycle[0].pose == .wide)
        #expect(cycle.contains { $0.pose == EyePose.wide.blinked })
    }
}

@Test func dormantBlinksSlowly() {
    for cycle in cycles(.dormant) {
        #expect(cycle[0].pose == .sleepy)
        #expect((8...14).contains(seconds([cycle[0]])))
    }
}

@Test func unreadBlinksNormallyBetweenEvents() {
    #expect(cycles(.unread).allSatisfy { !$0.contains { $0.pose == .happy } })
}

@Test func greetingsPlayOnlyForEvents() {
    #expect(AvatarMood.unread.greeting(from: .working).first?.pose == .happy)
    #expect(AvatarMood.unread.greeting(from: .waiting).first?.pose == .happy)
    #expect(AvatarMood.unread.greeting(from: .idle).isEmpty)
    #expect(AvatarMood.idle.greeting(from: .working).isEmpty)
    #expect(AvatarMood.failed.greeting(from: .working).map(\.pose) == [.squint, .rest])
    #expect(AvatarMood.failed.greeting(from: .failed).isEmpty)
    #expect(AvatarMood.working.greeting(from: .idle).isEmpty)
    #expect(AvatarMood.waiting.greeting(from: .working).isEmpty)
}

private final class Steps: Sendable {
    let count = Atomic<Int>(0)
}

private struct CountingClock: Clock {
    let steps: Steps
    let base = ContinuousClock()

    var now: ContinuousClock.Instant { base.now }
    var minimumResolution: Duration { base.minimumResolution }

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        steps.count.add(1, ordering: .relaxed)
        try await base.sleep(for: base.now.duration(to: deadline) / 40)
    }
}

@MainActor private func steps(rows: Int, mood: AvatarMood = .working, animate: Bool = true, phase: ScenePhase = .active) async throws -> Int {
    let steps = Steps()
    let list = List(0..<rows, id: \.self) { index in
        AvatarView(shape: .circle, color: "#22c55e", mood: mood, seed: "bot\(index)", size: rowAvatarSize)
    }
    .environment(\.avatarClock, CountingClock(steps: steps))
    .environment(\.avatarsAnimate, animate)
    .environment(\.scenePhase, phase)
    .environment(\.appearsActive, true)
    .frame(width: 300, height: 400)
    let window = NSWindow(contentRect: CGRect(x: -20000, y: 0, width: 300, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: list)
    window.contentView?.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .seconds(1.5))
    window.contentView = nil
    return steps.count.load(ordering: .relaxed)
}

@Test @MainActor func onlyAvatarsOnScreenMove() async throws {
    let perAvatar = Double(try await steps(rows: 4)) / 4
    let active = Double(try await steps(rows: 1000)) / perAvatar
    print("avatars moving in a 400 pt list of 1000 working bots: \(active) (\(perAvatar) steps each in 1.5 s at 40x)")
    #expect(perAvatar > 10)
    #expect(active < 25)
}

@Test @MainActor func aClosedInspectorAndTheBackgroundKeepTheEyesStill() async throws {
    #expect(try await steps(rows: 10, animate: false) == 0)
    #expect(try await steps(rows: 10, phase: .background) == 0)
}
