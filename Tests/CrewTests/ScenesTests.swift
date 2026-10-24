import Foundation
import Testing

@MainActor @Test func theFirstWindowRunsTheAppTasksUntilItCloses() {
    let scenes = Scenes()
    let main = UUID()
    let chat = UUID()

    scenes.claim(main)
    scenes.claim(chat)
    #expect(scenes.owner == main)

    scenes.release(chat)
    #expect(scenes.owner == main)

    scenes.release(main)
    #expect(scenes.owner == nil)
    scenes.claim(chat)
    #expect(scenes.owner == chat)
}

@MainActor @Test func aNewWindowTakesOverSoAStaleOwnerNeverBlocksTheAppTasks() {
    let scenes = Scenes()
    let vanished = UUID()
    let next = UUID()

    scenes.claim(vanished)
    scenes.take(next)
    #expect(scenes.owner == next)

    scenes.release(vanished)
    #expect(scenes.owner == next)
}

@MainActor @Test func aNewChatRequestIsTakenOnceSoADroppedOneNeverFiresLater() {
    let scenes = Scenes()
    scenes.newChat = .group

    #expect(scenes.takeNewChat() == .group)
    #expect(scenes.newChat == nil)
    #expect(scenes.takeNewChat() == nil)
}
