import SwiftUI

enum AvatarShape: String, CaseIterable, Identifiable, Sendable {
    case circle, blob, squircle, pill, triangle, hexagon, cloud, drop

    var id: String { rawValue }

    static func resolve(_ raw: String?) -> AvatarShape {
        raw.flatMap(AvatarShape.init(rawValue:)) ?? .circle
    }
}

enum AvatarMood: String, CaseIterable, Identifiable, Sendable {
    case idle, working, waiting, failed

    var id: String { rawValue }
}

enum AvatarExpression: String, CaseIterable, Identifiable, Sendable {
    case neutral, attentive, surprised, excited, happy, laughing, angry, sad
    case scared, wary, confused, curious, proud, shy, bored, sleepy

    var id: String { rawValue }

    static func resolve(_ raw: String?) -> AvatarExpression {
        raw.flatMap(AvatarExpression.init(rawValue:)) ?? .neutral
    }

    struct Eye: Equatable, Sendable {
        let width: Double
        let height: Double
        let tilt: Double
    }

    struct Eyes: Equatable, Sendable {
        let left: Eye
        let right: Eye
        let split: Double
    }

    var eyes: Eyes {
        switch self {
        case .neutral: Eyes(width: 0.186, height: 0.412, tilt: 0, split: 15.46)
        case .attentive: Eyes(width: 0.21, height: 0.44, tilt: 0, split: 16)
        case .surprised: Eyes(width: 0.45, height: 0.47, tilt: 0, split: 19)
        case .excited: Eyes(width: 0.4, height: 0.56, tilt: -10, split: 19.5)
        case .happy: Eyes(width: 0.27, height: 0.17, tilt: 14, split: 17)
        case .laughing: Eyes(width: 0.34, height: 0.13, tilt: 20, split: 18)
        case .angry: Eyes(width: 0.34, height: 0.15, tilt: 30, split: 17)
        case .sad: Eyes(width: 0.22, height: 0.4, tilt: -28, split: 16)
        case .scared: Eyes(width: 0.4, height: 0.6, tilt: 0, split: 20.5)
        case .wary: Eyes(left: Eye(width: 0.21, height: 0.4, tilt: 0), right: Eye(width: 0.22, height: 0.15, tilt: 0), split: 16)
        case .confused: Eyes(left: Eye(width: 0.2, height: 0.44, tilt: -18), right: Eye(width: 0.28, height: 0.17, tilt: 14), split: 16.5)
        case .curious: Eyes(left: Eye(width: 0.24, height: 0.46, tilt: -8), right: Eye(width: 0.2, height: 0.38, tilt: -8), split: 16.5)
        case .proud: Eyes(width: 0.3, height: 0.15, tilt: 18, split: 17)
        case .shy: Eyes(width: 0.17, height: 0.3, tilt: 0, split: 14)
        case .bored: Eyes(width: 0.3, height: 0.12, tilt: 0, split: 16)
        case .sleepy: Eyes(width: 0.2, height: 0.1764, tilt: 0, split: 16)
        }
    }
}

extension AvatarExpression.Eyes {
    init(width: Double, height: Double, tilt: Double, split: Double) {
        self.init(
            left: AvatarExpression.Eye(width: width, height: height, tilt: tilt),
            right: AvatarExpression.Eye(width: width, height: height, tilt: -tilt),
            split: split
        )
    }
}

struct AvatarColor: Identifiable, Sendable {
    let hex: String
    let name: String

    var id: String { hex }

    static let adaptiveHex = "#ffffff"
    static let fallbackHex = "#8b5cf6"

    static let palette = [
        AvatarColor(hex: adaptiveHex, name: "Auto"),
        AvatarColor(hex: "#a9703d", name: "Brown"),
        AvatarColor(hex: "#ef4444", name: "Red"),
        AvatarColor(hex: "#f97316", name: "Orange"),
        AvatarColor(hex: "#f59e0b", name: "Amber"),
        AvatarColor(hex: "#22c55e", name: "Green"),
        AvatarColor(hex: "#14b8a6", name: "Teal"),
        AvatarColor(hex: "#38bdf8", name: "Blue"),
        AvatarColor(hex: "#8b5cf6", name: "Purple"),
        AvatarColor(hex: "#ec4899", name: "Pink"),
        AvatarColor(hex: "#8e8e93", name: "Gray"),
    ]

    static func body(_ hex: String, in scheme: ColorScheme) -> Color {
        if hex.lowercased() == adaptiveHex { return scheme == .dark ? .white : .black }
        guard let rgb = rgb(hex) ?? rgb(fallbackHex) else { return .purple }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func eyes(on hex: String, in scheme: ColorScheme) -> Color {
        if hex.lowercased() == adaptiveHex { return scheme == .dark ? .black.opacity(0.85) : .white.opacity(0.9) }
        guard let rgb = rgb(hex) ?? rgb(fallbackHex) else { return .white.opacity(0.9) }
        let luminance = 255 * (0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue)
        return luminance < 110 ? .white.opacity(0.9) : .black.opacity(0.85)
    }

    private static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 7, value.first == "#", let packed = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return (Double(packed >> 16 & 0xff) / 255, Double(packed >> 8 & 0xff) / 255, Double(packed & 0xff) / 255)
    }
}

nonisolated struct AvatarBody: Shape {
    let shape: AvatarShape

    func path(in rect: CGRect) -> Path {
        let point = { (x: Double, y: Double) in CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        let unit = { (x: Double, y: Double, width: Double, height: Double) in
            CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height, width: width * rect.width, height: height * rect.height)
        }
        var path = Path()
        switch shape {
        case .circle:
            path.addEllipse(in: unit(0.08, 0.08, 0.84, 0.84))
        case .squircle:
            path.addRoundedRect(in: unit(0.08, 0.08, 0.84, 0.84), cornerSize: CGSize(width: 0.28 * rect.width, height: 0.28 * rect.height), style: .continuous)
        case .pill:
            path.addRoundedRect(in: unit(0.08, 0.23, 0.84, 0.54), cornerSize: CGSize(width: 0.27 * rect.width, height: 0.27 * rect.height))
        case .triangle, .hexagon:
            let corners = shape == .triangle
                ? [point(0.5, 0.06), point(0.94, 0.9), point(0.06, 0.9)]
                : [point(0.5, 0.06), point(0.92, 0.29), point(0.92, 0.71), point(0.5, 0.94), point(0.08, 0.71), point(0.08, 0.29)]
            let radius = (shape == .triangle ? 0.1 : 0.08) * rect.width
            let first = corners[0]
            let last = corners[corners.count - 1]
            path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
            for (index, corner) in corners.enumerated() {
                path.addArc(tangent1End: corner, tangent2End: corners[(index + 1) % corners.count], radius: radius)
            }
            path.closeSubpath()
        case .cloud:
            path.addEllipse(in: unit(0.08, 0.38, 0.48, 0.48))
            path.addEllipse(in: unit(0.28, 0.12, 0.5, 0.64))
            path.addEllipse(in: unit(0.55, 0.35, 0.38, 0.45))
        case .drop:
            path.move(to: point(0.5, 0.08))
            path.addCurve(to: point(0.92, 0.62), control1: point(0.72, 0.2), control2: point(0.92, 0.42))
            path.addCurve(to: point(0.08, 0.62), control1: point(0.92, 0.92), control2: point(0.08, 0.92))
            path.addCurve(to: point(0.5, 0.08), control1: point(0.08, 0.42), control2: point(0.28, 0.2))
            path.closeSubpath()
        case .blob:
            path.move(to: point(0.2, 0.17))
            path.addCurve(to: point(0.86, 0.2), control1: point(0.4, 0), control2: point(0.78, 0.02))
            path.addCurve(to: point(0.78, 0.86), control1: point(1, 0.4), control2: point(1, 0.72))
            path.addCurve(to: point(0.12, 0.78), control1: point(0.55, 1), control2: point(0.2, 1))
            path.addCurve(to: point(0.2, 0.17), control1: point(0, 0.6), control2: point(0, 0.3))
            path.closeSubpath()
        }
        return path
    }
}
