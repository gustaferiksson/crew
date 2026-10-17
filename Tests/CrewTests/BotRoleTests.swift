import Foundation
import Testing

private func roster(role: JSONValue?, revision: Int = 3) throws -> Bot {
    var meta: [String: JSONValue] = ["title": .string("Marlow"), "screenAutoOpen": .bool(true)]
    meta["role"] = role
    let row: [String: JSONValue] = [
        "name": .string("marlow"),
        "ui_meta": .object(["hermes-bots": .object(meta)]),
        "ui_meta_revisions": .object(["hermes-bots": .number(Double(revision))]),
    ]
    return try JSONDecoder().decode(Bot.self, from: JSONEncoder().encode(row))
}

private func encoded(_ meta: BotMeta) throws -> [String: JSONValue] {
    try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(meta))
}

@Test func roleRoundTripsNextToOtherClientsKeys() throws {
    let bot = try roster(role: .string("Chief of Staff"))
    #expect(bot.meta.role == "Chief of Staff")
    #expect(bot.role == "Chief of Staff")
    let object = try encoded(bot.meta)
    #expect(object["role"] == .string("Chief of Staff"))
    #expect(object["screenAutoOpen"] == .bool(true))
}

@Test func blankOrMissingRoleIsNoRole() throws {
    #expect(try roster(role: nil).role == nil)
    #expect(try roster(role: .null).role == nil)
    #expect(try roster(role: .string("  \n ")).role == nil)
    #expect(try encoded(roster(role: nil).meta)["role"] == nil)
}

@Test func multiLineRoleReadsAsOneLine() throws {
    #expect(try roster(role: .string(" Chief\nof Staff ")).role == "Chief of Staff")
}

@Test func draftPrefillsRoleWithoutBeingDirty() throws {
    let draft = ProfileDraft(bot: try roster(role: .string("Chief of Staff")))
    #expect(draft.fields.identity.role == "Chief of Staff")
    #expect(!draft.isDirty)
}

@Test func draftSendsEditedRoleAndKeepsOtherKeys() throws {
    let draft = ProfileDraft(bot: try roster(role: .string("Chief of Staff")))
    draft.fields.identity.role = "  Head of Ops "
    #expect(draft.isDirty)
    let edited = try encoded(draft.outgoingMeta(draft.fields.identity))
    #expect(edited["role"] == .string("Head of Ops"))
    #expect(edited["title"] == .string("Marlow"))
    #expect(edited["screenAutoOpen"] == .bool(true))

    draft.fields.identity.role = " "
    #expect(try encoded(draft.outgoingMeta(draft.fields.identity))["role"] == nil)
}

@Test func draftAdoptsNewerRoleOnlyWithoutUnsavedEdits() throws {
    let draft = ProfileDraft(bot: try roster(role: .string("Chief of Staff")))
    draft.adopt(try roster(role: .string("Head of Ops"), revision: 2))
    #expect(draft.fields.identity.role == "Chief of Staff")
    draft.adopt(try roster(role: .string("Head of Ops"), revision: 4))
    #expect(draft.fields.identity.role == "Head of Ops")
    #expect(!draft.isDirty)

    draft.fields.identity.title = "Marlowe"
    draft.adopt(try roster(role: .string("Archivist"), revision: 5))
    #expect(draft.fields.identity.role == "Head of Ops")
    #expect(draft.fields.identity.title == "Marlowe")
}
