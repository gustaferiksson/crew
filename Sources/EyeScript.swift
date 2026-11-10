import SwiftUI

struct EyeStep: Equatable {
    let pose: EyePose
    let animation: Animation?
    let hold: Duration
}

extension AvatarMood {
    var restingPose: EyePose {
        if self == .waiting { return .wide }
        return self == .dormant ? .sleepy : .rest
    }

    func greeting(from old: AvatarMood) -> [EyeStep] {
        guard old != self else { return [] }
        if self == .failed {
            return [
                EyeStep(pose: .squint, animation: .easeIn(duration: 0.12), hold: .milliseconds(570)),
                EyeStep(pose: .rest, animation: .smooth(duration: 0.35), hold: .milliseconds(350)),
            ]
        }
        return self == .unread && (old == .working || old == .waiting) ? happyBlink : []
    }

    func cycle(using generator: inout some RandomNumberGenerator) -> [EyeStep] {
        if self == .working { return reading(using: &generator) }
        if self == .dormant {
            let wait = EyeStep(pose: .sleepy, animation: nil, hold: .seconds(Double.random(in: 8...14, using: &generator)))
            return [
                wait,
                EyeStep(pose: EyePose.sleepy.blinked, animation: .easeIn(duration: 0.25), hold: .milliseconds(360)),
                EyeStep(pose: .sleepy, animation: .easeOut(duration: 0.3), hold: .milliseconds(300)),
            ]
        }
        let wait = EyeStep(pose: restingPose, animation: nil, hold: .seconds(Double.random(in: 3...8, using: &generator)))
        let blink = blink(from: restingPose)
        let twice = Int.random(in: 0..<6, using: &generator) == 0
        return [wait] + blink + (twice ? blink : [])
    }

    func reaction(to pokes: PokeTracker) -> [EyeStep] {
        let rest = restingPose
        if pokes.isGrumpy {
            return [
                EyeStep(pose: .grumpy, animation: .easeOut(duration: 0.2), hold: .milliseconds(2200)),
                EyeStep(pose: rest, animation: .smooth(duration: 0.4), hold: .milliseconds(400)),
            ]
        }
        return [
            EyeStep(pose: rest.blinked, animation: .easeIn(duration: 0.05), hold: .milliseconds(70)),
            EyeStep(pose: .startled, animation: .snappy(duration: 0.18), hold: .milliseconds(450)),
            EyeStep(pose: rest, animation: .smooth(duration: 0.35), hold: .milliseconds(350)),
        ]
    }

    var stillPoke: [EyeStep] {
        [EyeStep(pose: restingPose.blinked, animation: nil, hold: .milliseconds(180))]
    }

    private var happyBlink: [EyeStep] {
        [
            EyeStep(pose: .happy, animation: .easeOut(duration: 0.12), hold: .milliseconds(470)),
            EyeStep(pose: restingPose, animation: .easeInOut(duration: 0.2), hold: .milliseconds(200)),
        ]
    }

    private func blink(from pose: EyePose) -> [EyeStep] {
        [
            EyeStep(pose: pose.blinked, animation: .easeIn(duration: 0.07), hold: .milliseconds(180)),
            EyeStep(pose: pose, animation: .easeOut(duration: 0.12), hold: .milliseconds(120)),
        ]
    }

    private func reading(using generator: inout some RandomNumberGenerator) -> [EyeStep] {
        let pause = EyeStep(pose: .rest, animation: .smooth(duration: 0.35), hold: .seconds(Double.random(in: 2...5, using: &generator)))
        let lines = (0..<Int.random(in: 2...4, using: &generator)).flatMap { _ in
            [
                EyeStep(pose: .readingStart, animation: .easeOut(duration: 0.18), hold: .milliseconds(250)),
                EyeStep(pose: .readingEnd, animation: .easeInOut(duration: 1.1), hold: .seconds(Double.random(in: 1.2...1.4, using: &generator))),
            ]
        }
        return [pause] + lines + [EyeStep(pose: .rest, animation: .smooth(duration: 0.35), hold: .milliseconds(400))] + blink(from: .rest)
    }
}
