import Foundation
import Testing

private let approvals = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/approvals")

private func frame(_ name: String) throws -> ServerRequest {
    try JSONDecoder().decode(ServerRequest.self, from: Data(contentsOf: approvals.appending(path: "\(name).contract.v0.23.4.json")))
}

private func approval(_ name: String) throws -> ApprovalRequest {
    guard case .approval(let approval) = PendingRequest(try frame(name)) else { throw CocoaError(.coderReadCorrupt) }
    return approval
}

@Test func aFolderRequestNamesTheFolderAndTheAccessLevel() throws {
    let request = try approval("access")
    #expect(request.subject.title == "Allow folder access")
    #expect(request.subject.target == "/Users/crew-test/Documents/Trips")
    #expect(request.subject.access == "Read and write")
    #expect(request.risk == "The agent can change or delete files in this folder.")
    #expect(request.requestID == "8a41c6d0e2b94f37a5c1d7e03b9f6a28")
    #expect(!request.isPayment)
}

@Test func aSiteRequestNamesTheLabelOrElseTheHost() throws {
    let labelled = try approval("network")
    #expect(labelled.subject.title == "Allow site access")
    #expect(labelled.subject.target == "Open-Meteo weather")
    #expect(labelled.subject.host == "api.open-meteo.com")
    #expect(labelled.risk == "The agent can send data to this site.")
    let bare = try approval("network-host-only")
    #expect(bare.subject.target == "files.example.org")
    #expect(bare.subject.host == nil)
    #expect(bare.risk == nil)
}

@Test func anUnknownKindIsNeverAnEmptyCommandCard() throws {
    let request = try approval("unknown-kind")
    #expect(request.subject == .other)
    #expect(request.subject.title == "Permission needed")
    #expect(request.subject.target == nil)
    #expect(request.command.isEmpty)
}

@Test func folderAndSiteCardsOfferOnlyAlwaysBesidesAllowAndDeny() throws {
    let folder = try approval("access")
    #expect(folder.offers(.always) && !folder.offers(.session))
    let bare = try approval("network-host-only")
    #expect(!bare.offers(.always) && !bare.offers(.session))
    let unknown = try approval("unknown-kind")
    #expect(!unknown.offers(.always) && !unknown.offers(.session))
}

@Test func aCommandKeepsAllItsChoices() throws {
    let data = try Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/payments/approval-frame.json"))
    guard case .approval(let command) = PendingRequest(try JSONDecoder().decode(ServerRequest.self, from: data)) else { throw CocoaError(.coderReadCorrupt) }
    #expect(command.subject == .command)
    #expect(command.offers(.session) && command.offers(.always))
}

@Test func aSandboxRequestMarksTheBotAsWaitingForAnApproval() throws {
    #expect(WaitingKind(try frame("access")) == .approval)
    #expect(WaitingKind(try frame("network")) == .approval)
    #expect(WaitingKind(try frame("unknown-kind")) == .approval)
}

@Test func aRoomShowsTheSameSiteCardAsTheChat() throws {
    let data = try Data(contentsOf: approvals.appending(path: "room-network.contract.v0.23.4.json"))
    let action = try JSONDecoder().decode(RoomAction.self, from: data)
    let room = Room(id: "room-test", name: "Test Room", members: [RoomMember(memberID: "scout", profile: "scout", handle: "scout", displayName: "Scout")], createdAt: .distantPast, updatedAt: .distantPast)
    let session = GroupSession(fixture: room, events: [], driver: RoomState.Driver(pendingActions: [action]))
    guard case .approval(let request) = session.request else { throw CocoaError(.coderReadCorrupt) }
    #expect(request.subject.title == "Allow site access")
    #expect(request.subject.target == "Open-Meteo weather")
    #expect(request.requester == "Scout")
}

@Test func aDenyReasonIsTrimmedCappedAndSentOnlyWhenGiven() throws {
    func sent(_ answer: ApprovalAnswer) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(answer))
    }
    #expect(try sent(ApprovalAnswer(.deny, reason: "  Too broad for a weather check \n")) == ["choice": "deny", "reason": "Too broad for a weather check"])
    #expect(try sent(ApprovalAnswer(.deny, reason: "   ")) == ["choice": "deny"])
    #expect(try sent(ApprovalAnswer(.deny)) == ["choice": "deny"])
    #expect(try sent(ApprovalAnswer(.once, reason: "ignored")) == ["choice": "once"])
    #expect(try sent(ApprovalAnswer(.deny, reason: String(repeating: "a", count: 600)))["reason"]?.count == 500)
}
