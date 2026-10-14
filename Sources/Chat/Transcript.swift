import Foundation

nonisolated struct Transcript: Codable, Sendable, Equatable {
    var turns: [Turn] = []
}

nonisolated struct Turn: Identifiable, Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case streaming, complete, error, interrupted
    }

    var id: String
    var prompt: Prompt?
    var notice: String?
    var hiddenText: String?
    var work: [WorkItem] = []
    var reply = ""
    var status: Status
    var startedAt: Date
    var finishedAt: Date?
    var failure: String?
    var speaker: String?
}

nonisolated struct Prompt: Codable, Sendable, Equatable {
    var text: String
    var sentAt: Date
    var attachments: [Attachment] = []
    var mentionNote = ""
}

nonisolated struct WorkItem: Identifiable, Codable, Sendable, Equatable {
    enum Kind: Codable, Sendable, Equatable {
        case thinking(String)
        case note(String)
        case tool(ToolCall)
    }

    var id: String
    var kind: Kind
    var startedAt: Date
    var duration: TimeInterval?
}

nonisolated struct ToolCall: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case running, success, error
    }

    var name: String
    var subject: String
    var arguments: String
    var result: String?
    var outcome: String?
    var status: Status
}

nonisolated enum TurnEvent: Sendable {
    case messageStart
    case messageDelta(String)
    case reasoningDelta(String)
    case reasoningAvailable(String)
    case interim(String)
    case steered(String)
    case toolStart(id: String, name: String, context: String?, arguments: String)
    case toolComplete(id: String, duration: TimeInterval?, summary: String?, result: String)
    case messageComplete(text: String, status: Turn.Status, error: String?)
}

nonisolated struct HistoryRow: Decodable, Sendable {
    struct Call: Decodable, Sendable {
        struct Function: Decodable, Sendable {
            let name: String
            let arguments: String?
        }

        let id: String
        let function: Function
    }

    let id: Int
    let role: String
    let content: String?
    let toolCallId: String?
    let toolCalls: [Call]?
    let timestamp: Double
    let reasoning: String?
    let reasoningContent: String?
    let displayKind: String?
    let displayContent: String?
}

nonisolated func toolSubject(arguments: String) -> String {
    let object = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
    let preferred = ["command", "cmd", "path", "file_path", "query", "url", "pattern", "name", "goal", "prompt"]
    let value = preferred.lazy.compactMap { object[$0] as? String }.first
        ?? object.keys.sorted().lazy.compactMap { object[$0] as? String }.first
        ?? arguments
    return value.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
}

nonisolated func toolStatus(result: String) -> ToolCall.Status {
    guard let object = (try? JSONSerialization.jsonObject(with: Data(result.utf8))) as? [String: Any] else { return .success }
    if object["success"] as? Bool == false || object["ok"] as? Bool == false { return .error }
    if let status = object["status"] as? String, status.lowercased().contains(/error|fail|fatal|exception/) { return .error }
    let failureKeys = ["error", "errors", "failure", "exception"]
    let hasFailure = failureKeys.contains { key in
        guard let value = object[key], !(value is NSNull) else { return false }
        if let text = value as? String { return !text.isEmpty }
        if let list = value as? [Any] { return !list.isEmpty }
        if let flag = value as? Bool { return flag }
        return true
    }
    return hasFailure ? .error : .success
}

nonisolated func noticeText(kind: String?, content: String) -> String? {
    if kind == "model_switch" || content.hasPrefix("[System: The active model for this chat has changed to ") {
        let model = content.firstMatch(of: /changed to (.+?)(?: via provider .+?)?\. From/)?.1
        return model.map { String(localized: "Switched to \($0)") } ?? String(localized: "Model changed")
    }
    if kind == "personality_switch" { return String(localized: "Personality changed") }
    if kind == "auto_continue" { return String(localized: "Resumed interrupted turn") }
    if kind == "async_delegation_complete" { return String(localized: "Background work finished") }
    if kind == "process_complete" { return String(localized: "Background process finished") }
    return nil
}

extension Transcript {
    init(history rows: [HistoryRow]) {
        self.init()
        for row in rows.sorted(by: { $0.id < $1.id }) {
            let date = Date(timeIntervalSince1970: row.timestamp)
            let text = row.displayContent ?? row.content ?? ""
            if row.role == "user", row.displayKind == "steer", !turns.isEmpty {
                appendWork(.note(text), id: "\(row.id)-steer", at: date)
                continue
            }
            if row.role == "user" {
                let notice = noticeText(kind: row.displayKind, content: text)
                let prompt = notice == nil && row.displayKind != "hidden" ? Prompt(raw: text, sentAt: date) : nil
                let hiddenText = row.displayKind == "hidden" ? row.content ?? text : nil
                turns.append(Turn(id: String(row.id), prompt: prompt, notice: notice, hiddenText: hiddenText, status: .complete, startedAt: date, finishedAt: date))
                continue
            }
            if row.role == "assistant" {
                appendAssistant(row, at: date)
                continue
            }
            if row.role == "tool", let callID = row.toolCallId {
                completeTool(id: callID, result: row.content ?? "", summary: nil, duration: nil, at: date)
            }
        }
    }

    mutating func adoptIDs(from old: Transcript) {
        guard !turns.isEmpty else { return }
        let start = turns.lastIndex { turn in old.turns.contains { $0.id == turn.id } } ?? 0
        let offset = (old.turns.firstIndex { $0.id == turns[start].id } ?? start) - start
        for index in turns.indices.dropFirst(start) {
            guard old.turns.indices.contains(index + offset) else { return }
            let oldTurn = old.turns[index + offset]
            guard oldTurn.prompt?.text == turns[index].prompt?.text, oldTurn.notice == turns[index].notice else { return }
            if turns.allSatisfy({ $0.id != oldTurn.id }) { turns[index].id = oldTurn.id }
            for item in turns[index].work.indices where item < oldTurn.work.count {
                let previous = oldTurn.work[item]
                let current = turns[index].work[item].kind
                let bothThinking = if case .thinking = previous.kind, case .thinking = current { true } else { false }
                let bothNotes = if case .note = previous.kind, case .note = current { true } else { false }
                guard bothThinking || bothNotes, turns[index].work.allSatisfy({ $0.id != previous.id }) else { continue }
                turns[index].work[item].id = previous.id
            }
        }
    }

    mutating func begin(prompt text: String, attachments: [Attachment] = [], id: String = UUID().uuidString, at date: Date = .now) {
        turns.append(Turn(id: id, prompt: Prompt(text: text, sentAt: date, attachments: attachments), status: .streaming, startedAt: date))
    }

    mutating func begin(remote user: String, displayKind: String?, at date: Date) {
        let notice = noticeText(kind: displayKind, content: user)
        let prompt = Prompt(raw: user, sentAt: date)
        let isShown = notice == nil && displayKind != "hidden" && (!prompt.text.isEmpty || !prompt.attachments.isEmpty)
        turns.append(Turn(id: UUID().uuidString, prompt: isShown ? prompt : nil, notice: notice, hiddenText: displayKind == "hidden" ? user : nil, status: .streaming, startedAt: date))
    }

    mutating func apply(_ event: TurnEvent, at date: Date = .now) {
        if case .messageStart = event {
            if turns.last?.status != .streaming {
                turns.append(Turn(id: UUID().uuidString, status: .streaming, startedAt: date))
            }
            return
        }
        guard let index = turns.indices.last, turns[index].status == .streaming else { return }
        if case .messageDelta(let text) = event {
            turns[index].reply += text
            return
        }
        if case .reasoningDelta(let text) = event {
            if case .thinking(let previous) = turns[index].work.last?.kind {
                turns[index].work[turns[index].work.count - 1].kind = .thinking(previous + text)
            } else {
                appendWork(.thinking(text), id: UUID().uuidString, at: date)
            }
            return
        }
        if case .reasoningAvailable(let text) = event {
            appendWork(.thinking(text), id: UUID().uuidString, at: date)
            return
        }
        if case .interim(let text) = event {
            turns[index].reply = ""
            if turns[index].work.last?.kind != .note(text) {
                appendWork(.note(text), id: UUID().uuidString, at: date)
            }
            return
        }
        if case .steered(let text) = event {
            appendWork(.note(text), id: UUID().uuidString, at: date)
            return
        }
        if case .toolStart(let id, let name, let context, let arguments) = event {
            sealReplyAsNote(at: date)
            let call = ToolCall(name: name, subject: context ?? toolSubject(arguments: arguments), arguments: arguments, status: .running)
            appendWork(.tool(call), id: id, at: date)
            return
        }
        if case .toolComplete(let id, let duration, let summary, let result) = event {
            completeTool(id: id, result: result, summary: summary, duration: duration, at: date)
            return
        }
        if case .messageComplete(let text, let status, let error) = event {
            closeThinking(at: date)
            if !text.isEmpty { turns[index].reply = text }
            for workIndex in turns[index].work.indices {
                guard case .tool(var call) = turns[index].work[workIndex].kind, call.status == .running else { continue }
                call.status = .error
                call.outcome = "Interrupted"
                turns[index].work[workIndex].kind = .tool(call)
            }
            turns[index].status = status
            turns[index].failure = error
            turns[index].finishedAt = date
        }
    }

    private mutating func appendAssistant(_ row: HistoryRow, at date: Date) {
        if turns.isEmpty {
            turns.append(Turn(id: String(row.id), status: .complete, startedAt: date))
        }
        let index = turns.count - 1
        if let reasoning = row.reasoning ?? row.reasoningContent, !reasoning.isEmpty {
            appendWork(.thinking(reasoning), id: "\(row.id)-thinking", at: date)
        }
        let content = row.content ?? ""
        if let calls = row.toolCalls, !calls.isEmpty {
            if !content.isEmpty { appendWork(.note(content), id: "\(row.id)-note", at: date) }
            for call in calls {
                let arguments = call.function.arguments ?? ""
                let tool = ToolCall(name: call.function.name, subject: toolSubject(arguments: arguments), arguments: arguments, status: .success)
                appendWork(.tool(tool), id: call.id, at: date)
            }
        } else if !content.isEmpty {
            sealReplyAsNote(at: date)
            turns[index].reply = content
        }
        turns[index].finishedAt = date
    }

    private mutating func completeTool(id: String, result: String, summary: String?, duration: TimeInterval?, at date: Date) {
        guard let index = turns.indices.last,
              let workIndex = turns[index].work.lastIndex(where: { $0.id == id }),
              case .tool(var call) = turns[index].work[workIndex].kind
        else { return }
        call.result = result
        call.outcome = summary
        call.status = toolStatus(result: result)
        turns[index].work[workIndex].kind = .tool(call)
        turns[index].work[workIndex].duration = duration ?? date.timeIntervalSince(turns[index].work[workIndex].startedAt)
    }

    private mutating func sealReplyAsNote(at date: Date) {
        guard let index = turns.indices.last, !turns[index].reply.isEmpty else { return }
        appendWork(.note(turns[index].reply), id: UUID().uuidString, at: date)
        turns[index].reply = ""
    }

    private mutating func appendWork(_ kind: WorkItem.Kind, id: String, at date: Date) {
        closeThinking(at: date)
        turns[turns.count - 1].work.append(WorkItem(id: id, kind: kind, startedAt: date))
    }

    private mutating func closeThinking(at date: Date) {
        guard let index = turns.indices.last,
              let last = turns[index].work.last,
              case .thinking = last.kind,
              last.duration == nil
        else { return }
        turns[index].work[turns[index].work.count - 1].duration = date.timeIntervalSince(last.startedAt)
    }
}
