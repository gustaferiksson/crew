import Foundation
import Observation

@Observable
final class Scenes {
    private(set) var owner: UUID?
    var chatWindows: Set<Bot.ID> = []

    func take(_ scene: UUID) {
        owner = scene
    }

    func claim(_ scene: UUID) {
        if owner == nil { owner = scene }
    }

    func release(_ scene: UUID) {
        if owner == scene { owner = nil }
    }
}
