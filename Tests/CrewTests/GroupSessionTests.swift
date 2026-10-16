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
    let session = GroupSession(fixture: room, events: [], actions: [], isWorking: false)
    #expect(session.transcript.turns.isEmpty)
    #expect(session.threadID == "main")
    #expect(session.threads.map(\.title) == ["New Thread"])
}

@Test func threadsListNewestFirstWithOpeningLineAsTitle() {
    let session = GroupSession(fixture: room, events: events, actions: [], isWorking: false)
    #expect(session.threads == [RoomThread(id: "t2", title: "Weekend flights?"), RoomThread(id: "main", title: "Plan the launch")])
    #expect(session.threadID == "t2")
}

@Test func transcriptShowsOnlyTheSelectedThread() {
    let session = GroupSession(fixture: room, events: events, actions: [], isWorking: false)
    session.threadID = "main"
    #expect(session.transcript.turns.map(\.id) == ["welcome", "e1", "e2", "e5"])
}

@Test func deferredTurnOffersRetryOnlyWhileTheServerDoes() {
    let pending = GroupSession(fixture: room, events: events, actions: [retry], isWorking: false)
    let deferred = pending.transcript.turns.first { $0.id == "e4" }
    #expect(deferred?.status == .error)
    #expect(deferred?.speaker == "scout")
    #expect(deferred?.retryID == "t3")
    let settled = GroupSession(fixture: room, events: events, actions: [], isWorking: false)
    #expect(settled.transcript.turns.first { $0.id == "e4" }?.retryID == nil)
}

@Test func retryWithoutLoggedTurnGetsItsOwnRow() {
    let stalled = RoomAction(kind: "retry", memberID: nil, taskID: "t9", executionGeneration: nil, requestID: nil, approval: nil)
    let session = GroupSession(fixture: room, events: events, actions: [stalled], isWorking: false)
    #expect(session.transcript.turns.last?.retryID == "t9")
}

@Test func laterEventForTheSameTaskHidesTheDeferredRow() {
    let resolved = events + [event(6, "message.member", RoomEvent.Payload(text: "Found two.", memberID: "scout", threadID: "t2", taskID: "t3"))]
    let session = GroupSession(fixture: room, events: resolved, actions: [], isWorking: false)
    #expect(session.transcript.turns.map(\.id) == ["welcome", "e3", "e5", "e6"])
}
