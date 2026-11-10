import SwiftUI

struct AvatarView: View {
    let shape: AvatarShape
    let color: String
    let expression: AvatarExpression
    let mood: AvatarMood
    let photo: Image?
    let seed: String
    let pokes: Int
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.avatarsAnimate) private var avatarsAnimate
    @Environment(\.avatarClock) private var clock
    @Environment(\.avatarsFollowPointer) private var followsPointer
    @Environment(\.avatarFrozenPose) private var frozenPose
    @State private var pose: EyePose?
    @State private var settledMood: AvatarMood?
    @State private var glance: CGSize?
    @State private var tracker = PokeTracker()
    @State private var playedPokes = 0

    init(shape: AvatarShape, color: String, expression: AvatarExpression = .neutral, mood: AvatarMood = .idle, photo: Image? = nil, seed: String = "", pokes: Int = 0, size: CGFloat) {
        self.shape = shape
        self.color = color
        self.expression = expression
        self.mood = mood
        self.photo = photo
        self.seed = seed
        self.pokes = pokes
        self.size = size
    }

    var body: some View {
        if let photo {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: size * 0.84, height: size * 0.84)
                .clipShape(.rect(cornerRadius: size * 0.28, style: .continuous))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            AvatarFace(
                shape: shape,
                color: color,
                expression: mood == .failed ? .sad : expression,
                pose: frozenPose ?? shownPose,
                size: size
            )
            .animation(isLive && moves ? .snappy : nil, value: mood)
            .accessibilityHidden(true)
            .onContinuousHover { phase in
                guard case .active(let point) = phase else { return lookBack() }
                look(at: point)
            }
            .onChange(of: pokes) { tracker.poke(at: .now) }
            .task(id: isLive ? AvatarTaskKey(mood: mood, pokes: tracker.count, moves: moves) : nil) { await live() }
            .onDisappear {
                pose = nil
                glance = nil
            }
        }
    }

    private var isLive: Bool {
        scenePhase == .active && appearsActive && avatarsAnimate
    }

    private var moves: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var shownPose: EyePose {
        guard isLive else { return mood.restingPose }
        var shown = pose ?? mood.restingPose
        if let glance { shown.gaze = glance }
        return shown
    }

    private func look(at point: CGPoint) {
        guard followsPointer, moves else { return }
        withAnimation(.smooth(duration: 0.25)) { glance = EyePose.glance(at: point, size: size) }
    }

    private func lookBack() {
        guard glance != nil else { return }
        withAnimation(.smooth(duration: 0.4)) { glance = nil }
    }

    private func live() async {
        let previous = settledMood
        let poked = tracker.count > playedPokes
        settledMood = mood
        playedPokes = tracker.count
        guard isLive else {
            pose = nil
            return
        }
        guard moves else {
            _ = await play(poked ? mood.stillPoke : [])
            pose = nil
            return
        }
        if !poked {
            withAnimation(previous == nil ? nil : .smooth(duration: 0.35)) { pose = mood.restingPose }
        }
        var generator = SeededGenerator(seed: seed + mood.rawValue)
        var steps = poked ? mood.reaction(to: tracker) : previous.map { mood.greeting(from: $0) } ?? []
        while await play(steps) {
            steps = mood.cycle(using: &generator)
        }
    }

    private func play(_ steps: [EyeStep]) async -> Bool {
        for step in steps {
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                pose = mood.restingPose
            } else {
                withAnimation(step.animation) { pose = step.pose }
            }
            guard (try? await clock.sleep(for: step.hold, tolerance: .milliseconds(100))) != nil else { return false }
        }
        return !Task.isCancelled
    }
}
