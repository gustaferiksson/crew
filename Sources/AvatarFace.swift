import SwiftUI

struct AvatarFace: View {
    let shape: AvatarShape
    let color: String
    let expression: AvatarExpression
    let pose: EyePose
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let eyes = expression.eyes
        let pair = [eyes.left, eyes.right]
        let eyeColor = AvatarColor.eyes(on: color, in: colorScheme)
        ZStack {
            AvatarBody(shape: shape)
                .fill(AvatarColor.body(color, in: colorScheme))
            HStack(spacing: size * 0.1 * eyes.split / 15.46) {
                ForEach(pair.indices, id: \.self) { index in
                    let eye = pair[index]
                    Capsule()
                        .fill(eyeColor)
                        .frame(
                            width: size * 0.075 * eye.width / 0.186 * pose.scale * pose.stretch,
                            height: size * 0.22 * eye.height / 0.412 * pose.scale * pose.openness
                        )
                        .rotationEffect(.degrees(-18 + eye.tilt + (index == 0 ? pose.tilt : -pose.tilt)))
                }
            }
            .offset(x: size * (eyeAnchor.x * (1 - pose.centring) + pose.gaze.width), y: size * (eyeAnchor.y + pose.gaze.height))
        }
        .frame(width: size, height: size)
    }

    private var eyeAnchor: CGPoint {
        switch shape {
        case .triangle: CGPoint(x: 0.03, y: 0.14)
        case .cloud: CGPoint(x: 0.08, y: 0.04)
        case .drop: CGPoint(x: 0.08, y: 0.08)
        default: CGPoint(x: 0.12, y: -0.08)
        }
    }
}
