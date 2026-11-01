import SwiftUI

struct BotAvatar: View {
    let bot: Bot
    let status: BotStatus?
    let photo: Image?
    let size: CGFloat

    var body: some View {
        let look = bot.meta.look(name: bot.name)
        AvatarView(
            shape: look.shape,
            color: look.color,
            expression: .resolve(bot.meta.expression),
            mood: status.map { AvatarMood(status: $0, lastActive: bot.canonicalSession?.lastActive) } ?? .idle,
            photo: photo,
            seed: bot.name,
            size: size
        )
    }
}

extension AvatarMood {
    init(status: BotStatus, lastActive: Date?, now: Date = .now) {
        if case .waiting = status {
            self = .waiting
            return
        }
        if status == .working { self = .working; return }
        if status == .failed { self = .failed; return }
        if status == .unread { self = .unread; return }
        let dormant = lastActive.map { now.timeIntervalSince($0) >= 7 * 24 * 3600 } ?? false
        self = dormant ? .dormant : .idle
    }
}

extension BotMeta {
    func look(name: String) -> (shape: AvatarShape, color: String) {
        let isCustom = custom == true || shape != nil || color != nil
        if name.lowercased() == "default" && !isCustom { return (.squircle, AvatarColor.fallbackHex) }
        let hash = name.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        let shapes = AvatarShape.allCases.filter { $0 != .blob }
        let colors = ["#8b5cf6", "#38bdf8", "#14b8a6", "#22c55e", "#f59e0b", "#f97316", "#ef4444", "#ec4899"]
        return (
            shape.flatMap(AvatarShape.init(rawValue:)) ?? shapes[Int(hash % UInt64(shapes.count))],
            color ?? colors[Int(hash % UInt64(colors.count))]
        )
    }
}
