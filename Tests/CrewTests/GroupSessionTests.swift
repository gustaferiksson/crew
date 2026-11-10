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
    #expect(session.threadID == "main")
    #expect(session.threads.map(\.title) == ["New Thread"])
}

@Test func threadsListNewestFirstWithOpeningLineAsTitle() {
    let session = GroupSession(fixture: room, events: events, driver: RoomState.Driver())
    #expect(session.threads == [RoomThread(id: "t2", title: "Weekend flights?"), RoomThread(id: "main", title: "Plan the launch")])
    #expect(session.threadID == "t2")
}

@Test func transcriptShowsOnlyTheSelectedThread() {
    let session = GroupSession(fixture: room, events: events, driver: RoomState.Driver())
    session.threadID = "main"
    #expect(session.transcript.turns.map(\.id) == ["welcome", "e1", "e2", "e5"])
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
    #expect(session.transcript.turns.map(\.id) == ["welcome", "e3", "e5", "e6"])
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

    #expect(notices.map(\.0) == ["Crew Test and Crew Peer are in this group.", "Paused after 6 messages", "Continued", "Paused after 12 messages"])
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
    otherThread.threadID = "crew-probe"

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
