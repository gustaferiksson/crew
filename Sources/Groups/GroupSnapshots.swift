import SwiftUI

extension Snapshot {
    static let fixtureRoom = Room(
        id: "room-launch",
        name: "Launch Crew",
        members: [
            RoomMember(memberID: "ada", profile: "ada", handle: "ada", displayName: "Ada"),
            RoomMember(memberID: "forge", profile: "forge", handle: "forge", displayName: "Forge"),
            RoomMember(memberID: "scout", profile: "scout", handle: "scout", displayName: "Scout"),
        ],
        createdAt: .now.addingTimeInterval(-3 * 24 * 60 * 60),
        updatedAt: .now.addingTimeInterval(-20 * 60)
    )
}

struct GroupChatFixtureScreen: View {
    var body: some View {
        #if os(iOS)
        NavigationStack(path: .constant([0])) {
            Text("Crew")
                .navigationTitle("Crew")
                .navigationDestination(for: Int.self) { _ in chat }
        }
        #else
        NavigationStack { chat }
        #endif
    }

    private var chat: some View {
        let room = Snapshot.fixtureRoom
        let start = Date.now.addingTimeInterval(-6 * 60)
        let event = { (seq: Int, kind: String, profile: String?, payload: RoomEvent.Payload) in
            RoomEvent(seq: seq, eventID: "e\(seq)", kind: kind, actor: RoomEvent.Actor(profile: profile), payload: payload, createdAt: start.addingTimeInterval(Double(seq * 40)))
        }
        let events = [
            event(1, "message.user", nil, RoomEvent.Payload(text: "Can we ship 0.4.2 today? @forge can you check the publish?", threadID: "main")),
            event(2, "message.member", "ada", RoomEvent.Payload(text: "The migration dry run passed on staging, so the database side is ready.", memberID: "ada", threadID: "main", taskID: "t-ada")),
            event(3, "turn.deferred", nil, RoomEvent.Payload(memberID: "scout", threadID: "main", taskID: "t-scout")),
        ]
        let approval = ApprovalParams(command: "npm publish --tag latest", description: "Publishes crew-api 0.4.2 to the public registry.", choices: ["once", "deny"], toolName: "terminal", requestID: nil)
        let actions = [
            RoomAction(kind: "approval", memberID: "forge", taskID: "t-forge", executionGeneration: 1, requestID: "r1", approval: approval),
            RoomAction(kind: "retry", memberID: nil, taskID: "t-scout", executionGeneration: nil, requestID: nil, approval: nil),
        ]
        let paused = [
            event(1, "message.user", nil, RoomEvent.Payload(text: "Ada and Scout, agree on a launch time and @mention each other until you do.", threadID: "main")),
            event(2, "message.member", "ada", RoomEvent.Payload(text: "Thursday at 10:00 works for the database side. @scout does that suit you?", memberID: "ada", threadID: "main", discussionEventID: "e1")),
            event(3, "message.member", "scout", RoomEvent.Payload(text: "Thursday is tight for the store review, Friday at 9:00? @ada", memberID: "scout", threadID: "main", discussionEventID: "e1")),
            event(4, "message.member", "ada", RoomEvent.Payload(text: "Friday at 9:00 is fine if the dry run holds. @scout", memberID: "ada", threadID: "main", discussionEventID: "e1")),
            event(5, "room.activity", nil, RoomEvent.Payload(threadID: "main", status: "bounded", discussionEventID: "e1")),
        ]
        let working = RoomState.Driver(working: true, pendingActions: actions, memberActivity: [RoomState.Activity(memberID: "forge", status: "running", startedAt: start.addingTimeInterval(130), tool: "terminal")])
        let session = if Snapshot.requested == .groupWelcome {
            GroupSession(fixture: room, events: [], driver: RoomState.Driver())
        } else if Snapshot.requested == .groupChatPaused {
            GroupSession(fixture: room, events: paused, driver: RoomState.Driver(maxContinues: 5))
        } else {
            GroupSession(fixture: room, events: events, driver: working)
        }
        return GroupChatScreen(room: room, showsInspector: .constant(false), session: session) { _ in }
    }
}

struct GroupInspectorFixtureScreen: View {
    var body: some View {
        #if os(macOS)
        NavigationStack {
            ContentUnavailableView("Chat", systemImage: "bubble.left.and.bubble.right")
                .inspector(isPresented: .constant(true)) {
                    NavigationStack { inspector }
                        .inspectorColumnWidth(min: inspectorWidth.min, ideal: inspectorWidth.ideal, max: inspectorWidth.max)
                }
        }
        #else
        NavigationStack(path: .constant([0])) {
            Text("Crew")
                .navigationDestination(for: Int.self) { _ in inspector }
        }
        #endif
    }

    private var inspector: some View {
        GroupInspector(room: Snapshot.fixtureRoom, isPresented: .constant(true), histories: ["ada": RoomHistory(sessionID: "s-ada", messages: 1284), "forge": RoomHistory(sessionID: "s-forge", messages: 96), "scout": RoomHistory?.none]) { _ in }
    }
}
