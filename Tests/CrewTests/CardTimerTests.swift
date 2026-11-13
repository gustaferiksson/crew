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
    #expect(CardTimer(.string("ringing 12")) == .idle)
    #expect(CardTimer.path(for: "method/2~x") == "/crew-timer-method-2-x")
}

@MainActor private func pancakes(saved file: URL) throws -> SurfaceStore {
    let skill = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/Profile/crew-ui.SKILL.md"), encoding: .utf8)
    let recipe = try #require(markdownBlocks(from: skill).map { String($0.content.characters) }.first { $0.contains(#""seconds": 600"#) })
    let turn = Turn(id: "t1", prompt: Prompt(text: "Pancakes", sentAt: start), reply: "Pancakes.\n\n```a2ui\n\(recipe)\n```", status: .complete, startedAt: start, finishedAt: start)
    let store = SurfaceStore()
    store.saved = (CardState(fileURL: file), "chef")
    store.sync(Transcript(turns: [turn]))
    return store
}

@MainActor @Test func timersSurviveARelaunchAndOneThatEndedMeanwhileIsDone() throws {
    let file = URL.temporaryDirectory.appending(path: "crew-timers-\(UUID().uuidString)/cards.json")
    let store = try pancakes(saved: file)
    let model = try #require(store.processor.surfaceGroupModel["pancakes"])
    let steps = try #require(nodes(model.rootNode).first { $0.type == "Steps" })
    let timed = (steps.array(for: "items") ?? []).compactMap { $0 as? ResolvedDictionary }
    #expect(timed.count == 1)
    #expect(timed.first?.double(for: "seconds") == 600)

    let rest = CardTimer.path(for: "method-2")
    let other = CardTimer.path(for: "pizza")
    let now = Date.now
    model.dataModel.set(rest, value: CardTimer.idle.started(for: 600, at: now.addingTimeInterval(-700)).saved)
    model.dataModel.set(other, value: CardTimer.idle.started(for: 720, at: now).paused(at: now.addingTimeInterval(20)).saved)

    let relaunched = try pancakes(saved: file)
    let data = try #require(relaunched.processor.surfaceGroupModel["pancakes"]?.dataModel)
    #expect(CardTimer(data.get(rest)).isDone(at: .now), "the rest timer ended while Crew was closed")
    #expect(CardTimer(data.get(other)) == .paused(remaining: 700))

    data.set(rest, value: CardTimer.idle.saved)
    let reset = try pancakes(saved: file)
    #expect(CardTimer(reset.processor.surfaceGroupModel["pancakes"]?.dataModel.get(rest)) == .idle, "Reset survives a relaunch too")
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

@Test func aWholeModelBotUpdateKeepsTheTimers() {
    let cards = CardState(fileURL: nil)
    cards.userChanged(["/crew-timer-method-2": .string("paused 30"), "/servings": .number(6)], on: "pancakes:x", after: [], in: "chef")
    cards.botUpdated(["/"], with: "u1", on: "pancakes:x", in: "chef")
    #expect(cards.values(of: "pancakes:x", in: "chef") == ["/crew-timer-method-2": .string("paused 30")])
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
