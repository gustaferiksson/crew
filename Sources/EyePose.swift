import SwiftUI

struct EyePose: Equatable, Sendable {
    var openness = 1.0
    var scale = 1.0
    var stretch = 1.0
    var tilt = 0.0
    var gaze = CGSize.zero
    var centring = 0.0

    static let rest = EyePose()
    static let wide = EyePose(scale: 1.25, gaze: CGSize(width: 0, height: 0.02), centring: 0.8)
    static let squint = EyePose(openness: 0.22, stretch: 1.35)
    static let happy = EyePose(openness: 0.45, stretch: 1.3, gaze: CGSize(width: 0, height: -0.045))
    static let sleepy = EyePose(openness: 0.5, gaze: CGSize(width: 0, height: 0.02))
    static let readingStart = EyePose(gaze: CGSize(width: -0.04, height: 0))
    static let readingEnd = EyePose(gaze: CGSize(width: 0.04, height: 0))
    static let startled = EyePose(openness: 1.08, scale: 1.3)
    static let grumpy = EyePose(openness: 0.3, stretch: 1.4, gaze: CGSize(width: 0.05, height: 0.02))

    static func glance(at point: CGPoint, size: CGFloat) -> CGSize {
        let offset = CGSize(width: point.x / size - 0.5, height: point.y / size - 0.5)
        let reach = max(hypot(offset.width, offset.height), 0.25)
        return CGSize(width: offset.width / reach * 0.06, height: offset.height / reach * 0.04)
    }

    var blinked: EyePose {
        EyePose(openness: openness * 0.12, scale: scale, stretch: stretch, tilt: tilt, gaze: gaze, centring: centring)
    }
}

extension EnvironmentValues {
    @Entry var avatarClock: any Clock<Duration> = ContinuousClock()
    @Entry var avatarsAnimate = true
    @Entry var avatarsFollowPointer = false
    @Entry var avatarFrozenPose: EyePose?
}
