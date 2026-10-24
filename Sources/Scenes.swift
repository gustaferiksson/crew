import Foundation
import Observation

@Observable
final class Scenes {
    enum NewChat {
        case bot, group
    }

    private(set) var owner: UUID?
    var chatWindows: Set<Bot.ID> = []
    var newChat: NewChat?

    func take(_ scene: UUID) {
        owner = scene
    }

    func claim(_ scene: UUID) {
        if owner == nil { owner = scene }
    }

    func release(_ scene: UUID) {
        if owner == scene { owner = nil }
    }

    func takeNewChat() -> NewChat? {
        defer { newChat = nil }
        return newChat
    }
}
