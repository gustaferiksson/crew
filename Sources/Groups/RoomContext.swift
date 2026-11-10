import Foundation

nonisolated struct RoomContext: Codable, Equatable, Sendable {
    static let purposeLimit = 500
    static let notesLimit = 4096

    var purpose = ""
    var notes = ""
    var routing = "everyone"
    var leadMemberID = ""

    var answerer: String { routing == "lead" ? "lead:\(leadMemberID)" : routing }

    var purposeIsTooLong: Bool { Self.collapsed(purpose).count > Self.purposeLimit }
    var notesAreTooLong: Bool { notes.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count > Self.notesLimit }

    func applying(_ edit: RoomContextEdit) -> RoomContext {
        var next = self
        if case .purpose(let purpose) = edit { next.purpose = Self.collapsed(purpose) }
        if case .notes(let notes) = edit { next.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines) }
        if case .answerer(let answerer) = edit {
            let lead = answerer.hasPrefix("lead:") ? String(answerer.dropFirst(5)) : nil
            next.routing = lead == nil ? answerer : "lead"
            next.leadMemberID = lead ?? ""
        }
        return next
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case purpose, notes, routing
        case leadMemberID = "lead_member_id"
    }

    init(purpose: String = "", notes: String = "", routing: String = "everyone", leadMemberID: String = "") {
        self.purpose = purpose
        self.notes = notes
        self.routing = routing
        self.leadMemberID = leadMemberID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        routing = try container.decodeIfPresent(String.self, forKey: .routing).flatMap { $0.isEmpty ? nil : $0 } ?? "everyone"
        leadMemberID = try container.decodeIfPresent(String.self, forKey: .leadMemberID) ?? ""
    }

    func changes(since previous: RoomContext, names: (String) -> String) -> [String] {
        var lines: [String] = []
        if purpose != previous.purpose {
            let shown = purpose.count > 80 ? String(purpose.prefix(79)) + "…" : purpose
            lines.append(purpose.isEmpty ? String(localized: "Purpose removed") : String(localized: "Purpose: \(shown)"))
        }
        if notes != previous.notes {
            lines.append(notes.isEmpty ? String(localized: "Shared notes removed") : String(localized: "Shared notes updated"))
        }
        if answerer != previous.answerer {
            lines.append(
                routing == "lead" ? String(localized: "\(names(leadMemberID)) decides who answers")
                    : routing == "auto" ? String(localized: "Hermes picks who answers")
                    : String(localized: "Everyone answers")
            )
        }
        return lines
    }
}

nonisolated enum RoomContextEdit: Equatable, Sendable {
    case purpose(String)
    case notes(String)
    case answerer(String)
}

nonisolated struct RoomContextParams: Encodable, Equatable, Sendable {
    let roomID: String
    let eventID: String
    let purpose: String
    let notes: String
    var routing: String?
    var leadMemberID: String?

    init(roomID: String, eventID: String, saving edit: RoomContextEdit, onto current: RoomContext) {
        let context = current.applying(edit)
        self.roomID = roomID
        self.eventID = eventID
        purpose = context.purpose
        notes = context.notes
        guard case .answerer = edit else { return }
        routing = context.routing
        leadMemberID = context.leadMemberID
    }

    private enum CodingKeys: String, CodingKey {
        case purpose, notes, routing
        case roomID = "room_id"
        case eventID = "event_id"
        case leadMemberID = "lead_member_id"
    }
}
