import Foundation
import Testing

private let lead = RoomContext(purpose: "Plan the offsite", notes: "Budget 900 EUR", routing: "lead", leadMemberID: "ada")

private func sent(_ edit: RoomContextEdit, onto current: RoomContext = lead) throws -> NSDictionary? {
    let params = RoomContextParams(roomID: "room-1", eventID: "e1", saving: edit, onto: current)
    return try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? NSDictionary
}

@Test func purposeAndNotesSavesLeaveRoutingToTheServer() throws {
    #expect(try sent(.purpose("  Plan   the\noffsite in May ")) == ["room_id": "room-1", "event_id": "e1", "purpose": "Plan the offsite in May", "notes": "Budget 900 EUR"])
    #expect(try sent(.notes("\nBudget 950 EUR\n\nNo red-eyes\n")) == ["room_id": "room-1", "event_id": "e1", "purpose": "Plan the offsite", "notes": "Budget 950 EUR\n\nNo red-eyes"])
}

@Test func routingSavesSendTheServersPurposeAndNotesWithTheChoice() throws {
    #expect(try sent(.answerer("lead:scout")) == ["room_id": "room-1", "event_id": "e1", "purpose": "Plan the offsite", "notes": "Budget 900 EUR", "routing": "lead", "lead_member_id": "scout"])
    #expect(try sent(.answerer("auto")) == ["room_id": "room-1", "event_id": "e1", "purpose": "Plan the offsite", "notes": "Budget 900 EUR", "routing": "auto", "lead_member_id": ""])
    #expect(try sent(.answerer("everyone")) == ["room_id": "room-1", "event_id": "e1", "purpose": "Plan the offsite", "notes": "Budget 900 EUR", "routing": "everyone", "lead_member_id": ""])
}

@Test func anEditThatMatchesTheServerIsNoChange() {
    #expect(lead.applying(.purpose(" Plan  the offsite ")) == lead)
    #expect(lead.applying(.notes("Budget 900 EUR\n")) == lead)
    #expect(lead.applying(.answerer("lead:ada")) == lead)
    #expect(lead.applying(.answerer("everyone")) != lead)
}

@Test func limitsMatchTheServersAfterItsOwnNormalising() {
    #expect(!RoomContext(purpose: String(repeating: "a ", count: 250)).purposeIsTooLong)
    #expect(RoomContext(purpose: String(repeating: "a", count: 501)).purposeIsTooLong)
    #expect(!RoomContext(notes: String(repeating: "é", count: 2048) + "\n\n").notesAreTooLong)
    #expect(RoomContext(notes: String(repeating: "é", count: 2049)).notesAreTooLong)
}

@Test func olderContextsWithoutRoutingDecodeAsEveryone() throws {
    let context = try JSONDecoder().decode(RoomContext.self, from: Data(#"{"purpose": "p", "notes": "n"}"#.utf8))
    #expect(context == RoomContext(purpose: "p", notes: "n"))
}
