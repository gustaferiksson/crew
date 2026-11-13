import Foundation

nonisolated enum PinnedWidgetContent: Equatable, Sendable {
    case signedOut
    case missingBot
    case noPins
    case bot(VoiceBot, PinnedGlance?)

    init(bot name: String?, bots: [VoiceBot], glances: [String: PinnedGlance]) {
        guard !bots.isEmpty else {
            self = .signedOut
            return
        }
        if let name {
            self = bots.first { $0.name == name }.map { .bot($0, glances[name]) } ?? .missingBot
            return
        }
        let newest = bots.filter { !$0.hidden }.compactMap { bot in glances[bot.name].map { (bot: bot, glance: $0) } }.max { $0.glance.pinnedAt < $1.glance.pinnedAt }
        self = newest.map { .bot($0.bot, $0.glance) } ?? .noPins
    }

    var title: String {
        switch self {
        case .signedOut: String(localized: "Open Crew to sign in")
        case .missingBot: String(localized: "Choose a bot")
        case .noPins: String(localized: "No pinned cards")
        case .bot(let bot, let glance):
            glance.map { $0.title ?? String(localized: "Card from \(bot.title)") } ?? String(localized: "No pinned card")
        }
    }

    var detail: String? {
        switch self {
        case .signedOut, .missingBot: nil
        case .noPins: String(localized: "Pinned cards from your bots appear here.")
        case .bot(let bot, _): bot.title
        }
    }

    var symbol: String {
        switch self {
        case .signedOut: "person.crop.circle"
        case .missingBot: "questionmark.circle"
        case .noPins: "pin"
        case .bot(_, let glance): glance?.symbol ?? "pin.slash"
        }
    }

    var glance: PinnedGlance? {
        guard case .bot(_, let glance) = self else { return nil }
        return glance
    }

    var url: URL? {
        guard case .bot(let bot, _) = self else { return nil }
        return bot.chatURL
    }
}
