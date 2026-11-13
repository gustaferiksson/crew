import A2UICore
import Foundation
import Testing
import UserNotifications

private let start = Date(timeIntervalSince1970: 1_800_000_000)

@Test func startPauseAndResumeKeepTheRemainingTime() {
    let running = CardTimer.idle.started(for: 480, at: start)
    #expect(running == .running(until: start.addingTimeInterval(480)))
    #expect(running.remaining(of: 480, at: start.addingTimeInterval(100)) == 380)

    let paused = running.paused(at: start.addingTimeInterval(100))
    #expect(paused == .paused(remaining: 380))
    #expect(paused.remaining(of: 480, at: start.addingTimeInterval(5000)) == 380, "a paused timer doesn't count down")

    let resumed = paused.started(for: 480, at: start.addingTimeInterval(1000))
    #expect(resumed == .running(until: start.addingTimeInterval(1380)))
    #expect(!resumed.isDone(at: start.addingTimeInterval(1379)))
    #expect(resumed.isDone(at: start.addingTimeInterval(1380)))
    #expect(resumed.remaining(of: 480, at: start.addingTimeInterval(2000)) == 0)
    #expect(resumed.paused(at: start.addingTimeInterval(2000)) == resumed, "a finished timer stays Done")
}

@Test func theSavedStringRoundTrips() {
    for timer in [CardTimer.running(until: start), .paused(remaining: 312.5)] {
        #expect(CardTimer(timer.saved) == timer)
    }
    #expect(CardTimer.idle.saved == nil)
    #expect(CardTimer(nil) == .idle)
    #expect(CardTimer("ringing 12") == .idle)
}

@MainActor private func pancakes(servings: Int = 4) throws -> Transcript {
    let skill = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/Profile/crew-ui.SKILL.md"), encoding: .utf8)
    let recipe = try #require(markdownBlocks(from: skill).map { String($0.content.characters) }.first { $0.contains(#""seconds": 600"#) })
    let turn = { (id: String, servings: Int) in
        Turn(id: id, prompt: Prompt(text: "Pancakes", sentAt: start), reply: "Pancakes.\n\n```a2ui\n\(recipe.replacing(#""servings": 4, "baseServings": 4"#, with: #""servings": \#(servings), "baseServings": \#(servings)"#))\n```", status: .complete, startedAt: start, finishedAt: start)
    }
    return Transcript(turns: servings == 4 ? [turn("t1", 4)] : [turn("t1", 4), turn("t2", servings)])
}

@MainActor @Test func timersSurviveARelaunchAndOneThatEndedMeanwhileIsDone() throws {
    let file = URL.temporaryDirectory.appending(path: "crew-timers-\(UUID().uuidString)/timers.json")
    let timers = CardTimers(fileURL: file)
    let rest = CardTimers.key(chat: "chef", surface: "pancakes", timer: "method-2")
    let pizza = CardTimers.key(chat: "chef", surface: "dinner", timer: "pizza")
    let now = Date.now
    timers.set(CardTimer.idle.started(for: 600, at: now.addingTimeInterval(-700)), for: rest)
    timers.set(CardTimer.idle.started(for: 720, at: now).paused(at: now.addingTimeInterval(20)), for: pizza)

    let relaunched = CardTimers(fileURL: file)
    #expect(relaunched.timer(rest).isDone(at: .now), "the rest timer ended while Crew was closed")
    #expect(relaunched.timer(pizza) == .paused(remaining: 700))

    relaunched.set(.idle, for: rest)
    relaunched.clear("other")
    #expect(CardTimers(fileURL: file).timer(rest) == .idle, "Reset survives a relaunch too")
    #expect(CardTimers(fileURL: file).timer(pizza) == .paused(remaining: 700))
    relaunched.clear("chef")
    #expect(CardTimers(fileURL: file).entries.isEmpty, "deleting the bot clears its timers")
}

@MainActor @Test func aRunningTimerSurvivesTheBotResendingTheCard() throws {
    let store = SurfaceStore()
    store.saved = (CardState(fileURL: nil), "chef")
    store.sync(try pancakes())
    let first = try #require(store.processor.surfaceGroupModel["pancakes"])
    let steps = try #require(nodes(first.rootNode).first { $0.type == "Steps" })
    #expect((steps.array(for: "items") ?? []).compactMap { $0 as? ResolvedDictionary }.first?.double(for: "seconds") == 600)

    let timers = CardTimers(fileURL: nil)
    let running = CardTimer.idle.started(for: 600, at: .now)
    timers.set(running, for: CardTimers.key(chat: store.saved?.chat, surface: first.surfaceID, timer: "\(steps.id)-2"))

    store.sync(try pancakes(servings: 6))
    let resent = try #require(store.processor.surfaceGroupModel["pancakes"])
    #expect(resent !== first, "the re-send is a new card with a new fingerprint")
    #expect(resent.dataModel.get("/servings")?.numeric == 6)
    #expect(timers.timer(CardTimers.key(chat: store.saved?.chat, surface: resent.surfaceID, timer: "\(steps.id)-2")) == running)
}

@MainActor @Test func timerAlertsShowEvenInTheOpenChat() throws {
    let timer = try #require(PushRoute(userInfo: ["crew": ["profile": "chef", "kind": "timer"]]))
    let reply = try #require(PushRoute(userInfo: ["crew": ["profile": "chef"]]))
    #expect(PushCenter.presentation(for: timer, isActive: true, visibleBot: "chef") == [.banner, .list, .sound])
    #expect(PushCenter.presentation(for: reply, isActive: true, visibleBot: "chef") == [])
}

@MainActor @Test func theProbedRecipesBuildWithTimedSteps() throws {
    for (name, surface) in [("chat.a2ui-timer-risotto.history.json", "mushroom-risotto"), ("chat.a2ui-timer-chili.history.json", "chili-con-carne")] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/\(name)")
        let rows = try decoder.decode(TimerHistory.self, from: Data(contentsOf: file)).messages
        let store = SurfaceStore()
        store.sync(Transcript(history: rows))
        let steps = try #require(nodes(store.processor.surfaceGroupModel[surface]?.rootNode).first { $0.type == "Steps" }, "\(name)")
        let timed = (steps.array(for: "items") ?? []).compactMap { $0 as? ResolvedDictionary }.filter { ($0.double(for: "seconds") ?? 0) > 0 }
        #expect(timed.count == 5, "\(name)")
    }
}

nonisolated private struct TimerHistory: Decodable {
    let messages: [HistoryRow]
}

@Test func theAlertNamesTheCardAndTheStepAndAlwaysShows() throws {
    let request = CardTimer.alert(id: "timer.chef.pancakes.method-2", card: "Pancakes", what: "Let the batter rest.", chat: "chef", after: 380)
    #expect(request.identifier == "timer.chef.pancakes.method-2")
    #expect(request.content.title == "Pancakes")
    #expect(request.content.body == "Time's up: Let the batter rest.")
    #expect(request.content.interruptionLevel == .timeSensitive)
    let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
    #expect(trigger.timeInterval == 380)
    let route = try #require(PushRoute(userInfo: request.content.userInfo))
    #expect(route.profile == "chef")
    #expect(route.kind == "timer")
    #expect(CardTimer.alert(id: "x", card: nil, what: "Pizza", chat: nil, after: 0).content.title == "Timer")
}
