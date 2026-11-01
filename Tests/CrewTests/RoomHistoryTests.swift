import Foundation
import Testing

private let rooms = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/rooms")

private func decode<T: Decodable>(_ file: String, as type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: rooms.appending(path: file)))
}

@Test func aMemberRowShowsItsRecordedRoomHistoryLength() throws {
    let history = try decode("session.list.before.json", as: RoomSessionList.self).history

    #expect(history == RoomHistory(sessionID: "20261031_093355_b80a81", messages: 16))
    #expect(roomHistoryLabel(history, isPeer: false, isOnline: true) == "16 in history")
}

@Test func aMemberWithNoRoomSessionShowsNoHistoryAndCantCompress() throws {
    let history = try decode("session.list.none.json", as: RoomSessionList.self).history

    #expect(history == nil)
    #expect(roomHistoryLabel(.some(history), isPeer: false, isOnline: true) == "No history")
}

@Test func failedLookupsPeersAndOfflineRoomsShowNoCount() {
    #expect(roomHistoryLabel(nil, isPeer: false, isOnline: true) == "Unavailable")
    #expect(roomHistoryLabel(RoomHistory(sessionID: "s", messages: 3), isPeer: false, isOnline: false) == "Unavailable")
    #expect(roomHistoryLabel(RoomHistory(sessionID: "s", messages: 3), isPeer: true, isOnline: true) == nil)
}

@Test func theRecordedCompressReplyShowsHermesHeadline() throws {
    let reply = try decode("session.compress.json", as: RoomCompressReply.self)

    #expect(reply.outcome == .compressed("Compression refused (summary would grow the conversation): 16 messages preserved"))
}

@Test func compressRepliesThatDidNotCompressAreNotReportedAsDone() throws {
    let replies = [
        #"{"status": "pending", "turn_isolation": true, "message": "compression still running in the background; the transcript will refresh when it finishes"}"#,
        #"{"compressed": false, "lock_held": true, "message": "Another compression is already running for this session."}"#,
        #"{"status": "aborted", "summary": {"aborted": true, "headline": "Compression aborted", "note": "The summary model failed; nothing was removed."}}"#,
    ]

    let outcomes = try replies.map { try JSONDecoder().decode(RoomCompressReply.self, from: Data($0.utf8)).outcome }

    #expect(outcomes == [.pending, .busy("Another compression is already running for this session."), .aborted("The summary model failed; nothing was removed.")])
}

@Test func aPeerMemberIsRecognisedFromItsTarget() throws {
    let members = #"[{"member_id": "ada", "profile": "ada", "handle": "ada", "display_name": "Ada"}, {"member_id": "remote", "profile": "remote", "handle": "remote", "display_name": "Remote", "target": {"kind": "peer", "peer_id": "gw-2"}}]"#

    let decoded = try JSONDecoder().decode([RoomMember].self, from: Data(members.utf8))

    #expect(decoded.map(\.isPeer) == [false, true])
}
