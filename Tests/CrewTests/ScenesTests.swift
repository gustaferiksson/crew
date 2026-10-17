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
