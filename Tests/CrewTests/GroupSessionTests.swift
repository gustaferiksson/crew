import Foundation
import Testing

private let room = Room(
    id: "room-test",
    name: "Test Room",
    members: [
        RoomMember(memberID: "ada", profile: "ada", handle: "ada", displayName: "Ada"),
        RoomMember(memberID: "scout", profile: "scout", handle: "scout", displayName: "Scout"),
    ],
    createdAt: Date(timeIntervalSince1970: 0),
    updatedAt: Date(timeIntervalSince1970: 0)
)

private func event(_ seq: Int, _ kind: String, _ payload: RoomEvent.Payload) -> RoomEvent {
    RoomEvent(seq: seq, eventID: "e\(seq)", kind: kind, actor: RoomEvent.Actor(profile: nil), payload: payload, createdAt: Date(timeIntervalSince1970: Double(seq)))
}

private let events = [
    event(1, "message.user", RoomEvent.Payload(text: "Plan the launch\nwith details", threadID: "main")),
    event(2, "message.member", RoomEvent.Payload(text: "On it.", memberID: "ada", threadID: "main", taskID: "t1")),
    event(3, "message.user", RoomEvent.Payload(text: "Weekend flights?", threadID: "t2")),
    event(4, "turn.deferred", RoomEvent.Payload(memberID: "scout", threadID: "t2", taskID: "t3")),
    event(5, "room.renamed", RoomEvent.Payload(name: "Launch")),
]

private let retry = RoomAction(kind: "retry", memberID: nil, taskID: "t3", executionGeneration: nil, requestID: nil, approval: nil)

@Test func emptyRoomHasNoTurnsSoTheWelcomeShows() {
    let session = GroupSession(fixture: room, events: [], driver: RoomState.Driver())
    #expect(session.transcript.turns.isEmpty)
}

@Test func everySendOpensItsOwnThreadLikeHermesDesktop() throws {
    let session = GroupSession(fixture: room, events: events, driver: RoomState.Driver())
    let first = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.sendParams("Who can fix the build?"))) as? NSDictionary
    let second = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.sendParams("And the docs?"))) as? NSDictionary
    let firstID = try #require(first?["event_id"] as? String)
    let secondID = try #require(second?["event_id"] as? String)

    #expect(first == ["room_id": "room-test", "event_id": firstID, "payload": ["text": "Who can fix the build?", "thread_id": firstID]])
    #expect(second == ["room_id": "room-test", "event_id": secondID, "payload": ["text": "And the docs?", "thread_id": secondID]])
    #expect(firstID != secondID)
}

@Test func transcriptIsOneStreamOfEveryThread() {
    let session = GroupSession(fixture: room, events: events, driver: RoomState.Driver())
    #expect(session.transcript.turns.map(\.id) == ["welcome", "e1", "e2", "e3", "e4", "e5"])
}

@Test func deferredTurnOffersRetryOnlyWhileTheServerDoes() {
    let pending = GroupSession(fixture: room, events: events, driver: RoomState.Driver(pendingActions: [retry]))
    let deferred = pending.transcript.turns.first { $0.id == "e4" }
    #expect(deferred?.status == .error)
    #expect(deferred?.speaker == "scout")
    #expect(deferred?.retryID == "t3")
    let settled = GroupSession(fixture: room, events: events, driver: RoomState.Driver())
    #expect(settled.transcript.turns.first { $0.id == "e4" }?.retryID == nil)
}

@Test func retryWithoutLoggedTurnGetsItsOwnRow() {
    let stalled = RoomAction(kind: "retry", memberID: nil, taskID: "t9", executionGeneration: nil, requestID: nil, approval: nil)
    let session = GroupSession(fixture: room, events: events, driver: RoomState.Driver(pendingActions: [stalled]))
    #expect(session.transcript.turns.last?.retryID == "t9")
}

@Test func laterEventForTheSameTaskHidesTheDeferredRow() {
    let resolved = events + [event(6, "message.member", RoomEvent.Payload(text: "Found two.", memberID: "scout", threadID: "t2", taskID: "t3"))]
    let session = GroupSession(fixture: room, events: resolved, driver: RoomState.Driver())
    #expect(session.transcript.turns.map(\.id) == ["welcome", "e1", "e2", "e3", "e5", "e6"])
}

private let rooms = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/rooms")

private struct RecordedState: Decodable {
    let room: Room
    let driverStatus: RoomState.Driver

    private enum CodingKeys: String, CodingKey {
        case room
        case driverStatus = "driver_status"
    }
}

private func recorded<T: Decodable>(_ file: String, as type: T.Type) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(type, from: Data(contentsOf: rooms.appending(path: file)))
}

private func recordedRoom(_ log: String, state: String = "paused.state.json") throws -> GroupSession {
    let state = try recorded(state, as: RecordedState.self)
    return GroupSession(fixture: state.room, events: try recorded(log, as: [RoomEvent].self), driver: state.driverStatus)
}

private let discussion = (try? recorded("paused.log.json", as: [RoomEvent].self))?.first { $0.kind == "message.user" }?.eventID

@Test func aRoomPausedAtItsCapShowsAPausedRowWithContinue() throws {
    let session = try recordedRoom("paused.log.json")
    let pause = session.transcript.turns.last

    #expect(discussion?.hasPrefix("user:") == true)
    #expect(pause?.notice == "Paused after 6 messages")
    #expect(pause?.continueID == discussion)
    #expect(pause?.status == .complete)
}

@Test func continuedPauseLosesContinueAndTheNextPauseOffersIt() throws {
    let session = try recordedRoom("continued.log.json")
    let notices = session.transcript.turns.compactMap { turn in turn.notice.map { ($0, turn.continueID) } }

    #expect(notices.map(\.0) == ["Crew Test and Crew Peer are in this room.", "Paused after 6 messages", "Continued", "Paused after 12 messages"])
    #expect(notices.map(\.1) == [nil, nil, nil, discussion])
}

@Test func olderGatewaysWithoutContinueShowThePlainPausedRow() throws {
    let state = try recorded("paused.state.json", as: RecordedState.self)
    var driver = state.driverStatus
    driver.maxContinues = nil
    let session = GroupSession(fixture: state.room, events: try recorded("paused.log.json", as: [RoomEvent].self), driver: driver)

    #expect(session.transcript.turns.last?.notice == "Paused after 6 messages")
    #expect(session.transcript.turns.last?.continueID == nil)
}

@Test func usedUpContinuesLeaveThePausedRowWithoutContinue() throws {
    let state = try recorded("paused.state.json", as: RecordedState.self)
    var driver = state.driverStatus
    driver.maxContinues = 1
    let session = GroupSession(fixture: state.room, events: try recorded("continued.log.json", as: [RoomEvent].self), driver: driver)

    #expect(session.transcript.turns.last?.notice == "Paused after 12 messages")
    #expect(session.transcript.turns.last?.continueID == nil)
}

@Test func aNewMessageInTheThreadOrAStopRetiresThePause() throws {
    let state = try recorded("paused.state.json", as: RecordedState.self)
    let log = try recorded("paused.log.json", as: [RoomEvent].self)
    let later = { (kind: String, payload: RoomEvent.Payload) in
        RoomEvent(seq: 100, eventID: "later", kind: kind, actor: RoomEvent.Actor(profile: nil), payload: payload, createdAt: .now)
    }
    let pauseID = log.last?.eventID
    let sent = GroupSession(fixture: state.room, events: log + [later("message.user", RoomEvent.Payload(text: "New idea", threadID: "crew-probe"))], driver: state.driverStatus)
    let stopped = GroupSession(fixture: state.room, events: log + [later("room.stop_requested", RoomEvent.Payload())], driver: state.driverStatus)
    let otherThread = GroupSession(fixture: state.room, events: log + [later("message.user", RoomEvent.Payload(text: "Elsewhere", threadID: "other"))], driver: state.driverStatus)

    #expect(sent.transcript.turns.first { $0.id == pauseID }?.continueID == nil)
    #expect(stopped.transcript.turns.first { $0.id == pauseID }?.continueID == nil)
    #expect(otherThread.transcript.turns.first { $0.id == pauseID }?.continueID == discussion)
}

@Test func theWorkingRowNamesTheRunningMemberAndTimesItsTurn() throws {
    let session = try recordedRoom("paused.log.json", state: "paused.state.working.json")
    let working = session.transcript.turns.last
    let started = try #require(session.driver.memberActivity?.first?.startedAt)

    #expect(working?.id == "working")
    #expect(working?.startedAt == started)
    #expect(started != session.events.last?.createdAt)
    #expect(session.activity == "Crew Test")
}

@Test func theWorkingRowAddsEachRunningMembersToolAndSkipsQueuedOnes() {
    let activity = [
        RoomState.Activity(memberID: "scout", status: "running", startedAt: Date(timeIntervalSince1970: 40), tool: "web_search"),
        RoomState.Activity(memberID: "ada", status: "stopping", startedAt: Date(timeIntervalSince1970: 30)),
        RoomState.Activity(memberID: "forge", status: "queued"),
    ]
    let session = GroupSession(fixture: room, events: events, driver: RoomState.Driver(working: true, memberActivity: activity))

    #expect(session.activity == "Scout · web search, Ada")
    #expect(session.transcript.turns.last?.startedAt == Date(timeIntervalSince1970: 30))
}

private let wake = RoomAction(kind: "retry", memberID: "ada, scout", taskID: "prepare:room-test", executionGeneration: 1, requestID: nil, approval: nil)

@Test func aRoomThatCouldNotWakeItsMembersSaysWhyWithRetry() {
    let failed = GroupSession(fixture: room, events: events, driver: RoomState.Driver(pendingActions: [wake], lastError: "profile 'scout' not found"))
    let unexplained = GroupSession(fixture: room, events: events, driver: RoomState.Driver(pendingActions: [wake]))

    #expect(failed.transcript.turns.last?.failure == "Members couldn't be woken: profile 'scout' not found")
    #expect(failed.transcript.turns.last?.retryID == "prepare:room-test")
    #expect(unexplained.transcript.turns.last?.failure == "Members couldn't be woken.")
}

@Test func retrySendsThePendingActionsExactAttempt() throws {
    let session = GroupSession(fixture: room, events: events, driver: RoomState.Driver(pendingActions: [wake]))
    let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.retryParams(for: "prepare:room-test"))) as? NSDictionary
    let bare = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.retryParams(for: "t-unlisted"))) as? NSDictionary

    #expect(sent == ["room_id": "room-test", "task_id": "prepare:room-test", "member_id": "ada, scout", "execution_generation": 1])
    #expect(bare == ["room_id": "room-test", "task_id": "t-unlisted"])
}

@Test func roomSettingsShowAsNoticesOfWhatChanged() throws {
    let session = try recordedRoom("context.log.json", state: "context.state.json")
    let notices = session.transcript.turns.compactMap(\.notice)

    #expect(notices == [
        "Crew Test and Crew Peer are in this room.",
        "Purpose: Plan the team offsite in Lisbon\nShared notes updated",
        "Crew Test decides who answers",
        "Purpose: Plan the team offsite in Lisbon, 12 to 14 May",
        "Crew Test is taking this",
        "Hermes picks who answers",
        "Assigned to Crew Peer",
        "Purpose removed\nShared notes removed\nEveryone answers",
    ])
}

@Test func theLeadsRoutingTurnLeavesNoBubbleOnlyItsPick() throws {
    let session = try recordedRoom("context.log.json", state: "context.state.json")
    let replies = session.transcript.turns.filter { !$0.reply.isEmpty }

    #expect(replies.map(\.speaker) == ["crew-test", "crew-test", "crew-test-peer"])
    #expect(replies.allSatisfy { !$0.reply.contains("assign") })
}

@Test func automaticRoutingSaysWhoTheRouterPicked() throws {
    let session = try recordedRoom("context.log.json", state: "context.state.json")
    let turns = session.transcript.turns
    let routed = try #require(turns.firstIndex { $0.notice == "Assigned to Crew Peer" })

    #expect(turns[routed - 1].prompt?.text == "What is the weather like in Lisbon in May?")
    #expect(turns[routed + 1].speaker == "crew-test-peer")
}

@Test func aRoutinePostIsANoticeAndTheOwnersOutputNeverTheUsersBubble() throws {
    let session = try recordedRoom("context.routine.log.json", state: "context.routine.state.json")
    let turns = session.transcript.turns.filter { $0.id != "welcome" }

    #expect(turns.allSatisfy { $0.prompt == nil })
    #expect(turns.map(\.notice) == ["Routine: Daily fares", nil, nil])
    #expect(turns[1].speaker == "crew-test-peer")
    #expect(turns[1].reply.hasPrefix("Fares to Lisbon dropped to 129 EUR on TAP."))
    #expect(turns[2].speaker == "crew-test")
    #expect(!session.isAwaitingReply)
}

@Test func settingsSavedBeforeTheFirstMessageLeaveTheEmptyRoom() throws {
    let log = try recorded("context.log.json", as: [RoomEvent].self)
    let session = GroupSession(fixture: room, events: log.filter { $0.kind == "room.context_set" }, driver: RoomState.Driver())

    #expect(session.transcript.turns.isEmpty)
}

@Test func aLongPurposeIsShortenedInItsNotice() {
    let notice = RoomContext(purpose: String(repeating: "word ", count: 40)).changes(since: RoomContext()) { $0 }
    #expect(notice.first?.count == "Purpose: ".count + 80)
    #expect(notice.first?.hasSuffix("…") == true)
}

@Test func aFailedRoutineRunIsAnErrorUnderItsNotice() {
    let failed = RoomEvent(seq: 1, eventID: "cron-post:1", kind: "message.user", actor: RoomEvent.Actor(profile: nil, id: "cron-notice:job1", displayName: "[bot:ada] Daily fares"), payload: RoomEvent.Payload(text: "The job failed: model timeout", threadID: "cron-1"), createdAt: .now)
    let session = GroupSession(fixture: room, events: [failed], driver: RoomState.Driver())
    let turns = session.transcript.turns.filter { $0.id != "welcome" }

    #expect(turns.map(\.notice) == ["Routine: Daily fares", nil])
    #expect(turns[1].status == .error)
    #expect(turns[1].failure == "The job failed: model timeout")
}

@Test func aSentMessageKeepsTheRoomPollingUntilItsFirstEventLands() throws {
    let state = try recorded("context.state.json", as: RecordedState.self)
    let log = try recorded("context.log.json", as: [RoomEvent].self)
    let sent = try #require(log.firstIndex { $0.payload.threadID == "crew-probe-auto" })
    let routing = GroupSession(fixture: state.room, events: Array(log[...sent]), driver: state.driverStatus)
    let settled = GroupSession(fixture: state.room, events: log, driver: state.driverStatus)

    #expect(!state.driverStatus.working)
    #expect(routing.isAwaitingReply)
    #expect(!settled.isAwaitingReply)
}

@Test func replyContinuesTheMembersThreadAddressedToIt() throws {
    let session = try recordedRoom("context.log.json", state: "context.state.json")
    let answer = try #require(session.events.first { $0.kind == "message.member" })
    let target = try #require(session.reply(to: answer.eventID))

    #expect(target.thread == "crew-probe-lead")
    #expect(target.handle == "crew-test")
    #expect(target.name == "Crew Test")
    #expect(target.quote == answer.payload.text?.split(separator: "\n").first.map(String.init))

    let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.sendParams("@crew-test And Sunday?", thread: target.thread))) as? NSDictionary
    let id = try #require(sent?["event_id"] as? String)
    #expect(sent == ["room_id": session.room.id, "event_id": id, "payload": ["text": "@crew-test And Sunday?", "thread_id": "crew-probe-lead"]])
    #expect(id != target.thread)
}

@Test func replyToYourOwnMessageNamesNobody() throws {
    let session = try recordedRoom("context.log.json", state: "context.state.json")
    let prompt = try #require(session.events.first { $0.kind == "message.user" })
    let target = try #require(session.reply(to: prompt.eventID))

    #expect(target == ReplyTarget(messageID: prompt.eventID, thread: "crew-probe-lead", name: "You", handle: nil, quote: "Which day should we fly out?"))
    #expect(target.addressing("Or Friday?", replacing: nil) == "Or Friday?")
}

@Test func onlyLoggedMessagesOfferReply() throws {
    let session = try recordedRoom("context.log.json", state: "context.state.json")
    let offered = session.transcript.turns.filter { $0.thread != nil }.map(\.id)
    let messages = session.events.filter { ["message.user", "message.member"].contains($0.kind) }.map(\.eventID)
    #expect(offered == messages)
    #expect(session.transcript.turns.filter { $0.notice != nil }.allSatisfy { $0.thread == nil && session.reply(to: $0.id) == nil })

    let routine = try recordedRoom("context.routine.log.json", state: "context.routine.state.json")
    let post = try #require(routine.events.first { $0.routineTitle != nil })
    #expect(routine.reply(to: post.eventID) == nil)
    #expect(routine.transcript.turns.first { $0.id == post.eventID }?.thread == nil)

    routine.send("Hello")
    #expect(routine.transcript.turns.last { $0.prompt != nil }?.thread == nil)
}

@Test func replyQuotesTheFirstPlainLine() {
    let card = "```a2ui\n[]\n```\n\n**Widerøe** at _07:40_\n\nIt lands at 09:10."
    let rows = [
        event(1, "message.member", RoomEvent.Payload(text: card, memberID: "ada", threadID: "main")),
        event(2, "message.member", RoomEvent.Payload(text: "```a2ui\n[]\n```", memberID: "scout", threadID: "main")),
    ]
    let session = GroupSession(fixture: room, events: rows, driver: RoomState.Driver())

    #expect(session.reply(to: "e1")?.quote == "Widerøe at 07:40")
    #expect(session.reply(to: "e2")?.quote == "")
    #expect(session.reply(to: "e2")?.name == "Scout")
}

@Test func replyPutsTheHandleFirstOnceAndSwapsItsOwnOldOne() {
    let ada = ReplyTarget(messageID: "e1", thread: "main", name: "Ada", handle: "ada", quote: "")
    let scout = ReplyTarget(messageID: "e2", thread: "main", name: "Scout", handle: "scout", quote: "")
    let me = ReplyTarget(messageID: "e3", thread: "main", name: "You", handle: nil, quote: "")

    #expect(ada.addressing("", replacing: nil) == "@ada ")
    #expect(ada.addressing("Is it booked?", replacing: nil) == "@ada Is it booked?")
    #expect(ada.addressing("@ada Is it booked?", replacing: nil) == "@ada Is it booked?")
    #expect(scout.addressing("@ada Is it booked?", replacing: ada) == "@scout Is it booked?")
    #expect(me.addressing("@ada Is it booked?", replacing: ada) == "Is it booked?")
}

@Test func aReplyIntoAWorkingThreadSaysWhyTheAnswerStopped() throws {
    let session = try recordedRoom("reply.log.json", state: "reply.state.json")
    let superseded = try #require(session.events.first { $0.kind == "turn.cancelled" && $0.payload.reason == "superseded_by_newer_user_event" })
    let turn = try #require(session.transcript.turns.first { $0.id == superseded.eventID })
    #expect(turn.status == .interrupted)
    #expect(turn.stopReason == "Stopped for your newer message")

    let stopped = RoomEvent(seq: 999, eventID: "stop", kind: "turn.cancelled", actor: superseded.actor, payload: RoomEvent.Payload(memberID: superseded.payload.memberID, threadID: superseded.payload.threadID, reason: "member turn cancelled"), createdAt: .now)
    let plain = GroupSession(fixture: session.room, events: session.events + [stopped], driver: RoomState.Driver())
    #expect(plain.transcript.turns.first { $0.id == "stop" }?.status == .interrupted)
    #expect(plain.transcript.turns.first { $0.id == "stop" }?.stopReason == nil)
}

@Test func recordedRepliesStayInTheOpenersThreadAndSkipTheLead() throws {
    let session = try recordedRoom("reply.log.json", state: "reply.state.json")
    let prompts = session.events.filter { $0.kind == "message.user" }
    let thread = try #require(prompts.first?.payload.threadID)
    let assigned = Set(session.events.filter { $0.kind == "room.assignment" }.compactMap(\.payload.discussionEventID))

    #expect(prompts.count >= 4)
    #expect(prompts.allSatisfy { $0.payload.threadID == thread })
    #expect(assigned.isDisjoint(with: prompts.dropFirst().map(\.eventID)))
}
