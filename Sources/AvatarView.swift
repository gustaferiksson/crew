import SwiftUI

struct AvatarView: View {
    let shape: AvatarShape
    let color: String
    let expression: AvatarExpression
    let mood: AvatarMood
    let photo: Image?
    let seed: String
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.avatarsAnimate) private var avatarsAnimate
    @Environment(\.avatarClock) private var clock
    @State private var pose: EyePose?
    @State private var settledMood: AvatarMood?

    init(shape: AvatarShape, color: String, expression: AvatarExpression = .neutral, mood: AvatarMood = .idle, photo: Image? = nil, seed: String = "", size: CGFloat) {
        self.shape = shape
        self.color = color
        self.expression = expression
        self.mood = mood
        self.photo = photo
        self.seed = seed
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
                pose: animates ? pose ?? mood.restingPose : mood.restingPose,
                size: size
            )
            .animation(animates ? .snappy : nil, value: mood)
            .accessibilityHidden(true)
            .task(id: animates ? mood : nil) { await live() }
        }
    }

    private var animates: Bool {
        !reduceMotion && scenePhase == .active && appearsActive && avatarsAnimate
    }

    private func live() async {
        let previous = settledMood
        settledMood = mood
        guard animates else { return }
        withAnimation(previous == nil ? nil : .smooth(duration: 0.35)) { pose = mood.restingPose }
        var generator = SeededGenerator(seed: seed + mood.rawValue)
        var steps = previous.map { mood.greeting(from: $0) } ?? []
        while !Task.isCancelled {
            for step in steps {
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    pose = mood.restingPose
                } else {
                    withAnimation(step.animation) { pose = step.pose }
                }
                guard (try? await clock.sleep(for: step.hold, tolerance: .milliseconds(100))) != nil else { return }
            }
            steps = mood.cycle(using: &generator)
        }
    }
}
