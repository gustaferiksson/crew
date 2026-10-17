import SwiftUI

struct AvatarView: View {
    let shape: AvatarShape
    let color: String
    let expression: AvatarExpression
    let mood: AvatarMood
    let photo: Image?
    let seed: String
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false
    @State private var swaying = false
    @State private var workingSince = Date.now

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
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !swaying)) { context in
                face(at: context.date)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: mood == .working && !reduceMotion) { await sway() }
            .task(id: reduceMotion) { await blink() }
        }
    }

    private func face(at date: Date) -> some View {
        let shown = mood == .waiting ? .curious : mood == .failed ? .sad : expression
        let eyes = shown.eyes
        let pair = [eyes.left, eyes.right]
        let elapsed = date.timeIntervalSince(workingSince)
        let swing = mood == .working && !reduceMotion ? min(1, max(0, (30 - elapsed) / 2)) : 0
        let lean = mood == .working ? 1.0 : 0
        let rotation = lean * -5 + swing * (sin(elapsed * 0.42) * 6 + sin(elapsed * 0.75) * 2.5)
        let gazeX = lean * -0.03 + swing * sin(elapsed * 0.55) * 0.06
        let gazeY = lean * -0.03 + swing * sin(elapsed * 0.38) * 0.04
        let eyeColor = AvatarColor.eyes(on: color, in: colorScheme)
        return ZStack {
            AvatarBody(shape: shape)
                .fill(AvatarColor.body(color, in: colorScheme))
            HStack(spacing: size * 0.1 * eyes.split / 15.46) {
                ForEach(pair.indices, id: \.self) { index in
                    let eye = pair[index]
                    Capsule()
                        .fill(eyeColor)
                        .frame(width: size * 0.075 * eye.width / 0.186, height: size * 0.22 * eye.height / 0.412 * (blinking ? 0.12 : 1))
                        .rotationEffect(.degrees(-18 + eye.tilt))
                }
            }
            .offset(x: size * (eyeAnchor.x + gazeX), y: size * (eyeAnchor.y + gazeY))
        }
        .rotationEffect(.degrees(rotation), anchor: UnitPoint(x: 0.5, y: 0.7))
        .animation(reduceMotion ? nil : .snappy, value: shown)
        .animation(reduceMotion ? nil : .smooth, value: lean)
    }

    private var eyeAnchor: CGPoint {
        switch shape {
        case .triangle: CGPoint(x: 0.03, y: 0.14)
        case .cloud: CGPoint(x: 0.08, y: 0.04)
        case .drop: CGPoint(x: 0.08, y: 0.08)
        default: CGPoint(x: 0.12, y: -0.08)
        }
    }

    private func sway() async {
        guard mood == .working, !reduceMotion else {
            swaying = false
            return
        }
        workingSince = .now
        swaying = true
        try? await Task.sleep(for: .seconds(30))
        swaying = false
    }

    private func blink() async {
        guard !reduceMotion else { return }
        let hash = seed.unicodeScalars.reduce(UInt32(2_166_136_261)) { ($0 ^ $1.value) &* 16_777_619 }
        let period = 3 + Double(hash % 2000) / 1000
        var delay = 6 + Double(hash % 997) / 997 * period
        while (try? await Task.sleep(for: .seconds(delay))) != nil {
            withAnimation(.easeIn(duration: 0.07)) { blinking = true }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.12)) { blinking = false }
            delay = period
        }
    }
}
