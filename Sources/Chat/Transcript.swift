import Foundation

nonisolated struct Transcript: Codable, Sendable, Equatable {
    var turns: [Turn] = []
    var waiting: [Turn] = []
}

nonisolated struct LastMessage: Hashable, Sendable {
    let text: String
    let date: Date
}

nonisolated struct Turn: Identifiable, Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case streaming, complete, error, interrupted
    }

    enum Pending: String, Codable, Sendable {
        case steer, taken, queued
    }

    var id: String
    var prompt: Prompt?
    var notice: String?
    var agentMessage: AgentMessage?
    var delivery: String?
    var deliveryFailure: DeliveryFailure?
    var hiddenText: String?
    var work: [WorkItem] = []
    var reply = ""
    var status: Status
    var startedAt: Date
    var finishedAt: Date?
    var failure: String?
    var speaker: String?
    var retryID: String?
    var pending: Pending?
    var isSteer = false
    var answer: String?
}

nonisolated struct Prompt: Codable, Sendable, Equatable {
    var text: String
    var sentAt: Date
    var attachments: [Attachment] = []
    var mentionNote = ""
}

nonisolated struct AgentMessage: Codable, Sendable, Equatable {
    var sender: String
    var handle: String
    var body: String

    init?(_ text: String) {
        let pattern = /(?s)(?:Message from (?:🤖\s*)?([^:\n(]{1,64}?)(?:\s*\(@([a-z0-9][a-z0-9_-]{0,63})(?:@[a-zA-Z0-9][a-zA-Z0-9_-]{0,63})?\))?:\s*|\[Message from agent '([^']{1,64})'\]\s*)(.*)/
        guard let match = text.trimmingCharacters(in: .whitespacesAndNewlines).wholeMatch(of: pattern) else { return nil }
        sender = String(match.1 ?? match.3 ?? "agent").trimmingCharacters(in: .whitespaces)
        let handle = String(match.2 ?? match.3 ?? Substring(sender)).trimmingCharacters(in: .whitespaces).lowercased()
        self.handle = handle == "hermes" ? "default" : handle
        body = match.4.trimmingCharacters(in: .whitespacesAndNewlines)
    }
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

    var messagedHandle: String? {
        guard case .tool(let call) = kind, call.name == "message_agent", call.result?.contains("\"process_id\"") == true else { return nil }
        let target = ((try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any])?["target"] as? String ?? ""
        let handle = target.trimmingCharacters(in: .whitespaces).trimmingPrefix("@").prefix { $0 != "@" }.lowercased()
        return handle == "hermes" ? "default" : handle
    }
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

        var tool: (name: String, arguments: String) {
            let stored = function.arguments ?? ""
            guard function.name == "tool_call",
                  let object = (try? JSONSerialization.jsonObject(with: Data(stored.utf8))) as? [String: Any]
            else { return (function.name, stored) }
            let entries = object["calls"].map { $0 as? [[String: Any]] ?? [] } ?? [object]
            guard entries.count == 1, let name = entries[0]["name"] as? String else { return (function.name, stored) }
            let inner = entries[0]["arguments"]
            if let text = inner as? String { return (name, text) }
            guard let inner, JSONSerialization.isValidJSONObject(inner), let data = try? JSONSerialization.data(withJSONObject: inner, options: [.sortedKeys, .withoutEscapingSlashes]) else { return (name, "{}") }
            return (name, String(decoding: data, as: UTF8.self))
        }
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
    let displayCommentary: [String]?
    let displayReasoning: String?
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
    if kind == "hidden", let host = content.wholeMatch(of: /I added https:\/\/(\S+) to your shops\. Continue the purchase\./)?.1 {
        return String(localized: "Added \(String(host)) to Shops")
    }
    if kind == "personality_switch" { return String(localized: "Personality changed") }
    if kind == "auto_continue" { return String(localized: "Resumed interrupted turn") }
    if kind == "async_delegation_complete" { return String(localized: "Background work finished") }
    if kind == "process_complete" { return String(localized: "Background process finished") }
    return nil
}

nonisolated func deliveryProcess(in content: String) -> String? {
    guard content.hasPrefix("[IMPORTANT: Background process "), content.contains("bot_mode_dm.py --run-delivery") else { return nil }
    return content.firstMatch(of: /proc_[0-9a-f]+/).map { String($0.output) }
}

nonisolated struct DeliveryFailure: Codable, Sendable, Equatable {
    var reason: String?
    var detail: String?
    var isUnconfirmed = false
    var target: String?
}

nonisolated extension DeliveryFailure {
    init?(notice: String) {
        guard deliveryProcess(in: notice) != nil else { return nil }
        let body = notice.firstRange(of: "\nOutput:\n").map { String(notice[$0.upperBound...]) } ?? ""
        let output = (body.hasSuffix("]") ? String(body.dropLast()) : body).trimmingCharacters(in: .whitespacesAndNewlines)
        let object = output.split(separator: "\n").reversed().lazy.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }.first
        let status = object?["status"] as? String ?? ""
        let isUnconfirmed = ["ambiguous", "queued", "claimed"].contains(status) || output.contains(#/(?m)^No reply from /#)
        guard !notice.contains("completed normally (exit code 0)") || isUnconfirmed || ["failed", "cancelled"].contains(status) else { return nil }
        if let object {
            self.init(reason: object["reason"] as? String, detail: (object["error"] ?? object["detail"]) as? String, isUnconfirmed: isUnconfirmed)
        } else if let tagged = output.firstMatch(of: /failed \[reason: ([a-z_]+)\]: (.+)/) {
            self.init(reason: String(tagged.1), detail: String(tagged.2))
        } else {
            self.init(isUnconfirmed: isUnconfirmed)
        }
    }

    func headline(for bot: String) -> String {
        if isUnconfirmed { return String(localized: "Delivery to \(bot) couldn't be confirmed.") }
        if ["runtime_offline", "queued_expired", "target_busy", "cancelled", "agent_blocked", "target_scope_unresolved"].contains(reason ?? "") { return String(localized: "Not delivered.") }
        if explanation(for: bot) != nil { return String(localized: "\(bot) couldn't answer.") }
        return String(localized: "Message to \(bot) failed.")
    }

    func explanation(for bot: String) -> String? {
        let sentences = [
            "target_busy": String(localized: "\(bot) is busy right now. Ask again later."),
            "runtime_offline": String(localized: "\(bot) is offline. Ask again when it's back."),
            "delivery_timeout": String(localized: "\(bot) didn't answer in time. It may have seen the message; ask again if it matters."),
            "queued_expired": String(localized: "\(bot)'s computer wasn't reachable in time. Ask again when it's back online."),
            "cancelled": String(localized: "The message to \(bot) was cancelled. Ask again if you still need it."),
            "provider_rate_limit": String(localized: "\(bot)'s AI provider is limiting requests. Ask again in a few minutes."),
            "provider_server_error": String(localized: "\(bot)'s AI provider had an error. Ask again later."),
            "provider_auth_or_access": String(localized: "\(bot)'s AI provider rejected its login or access. Asking again won't help."),
            "provider_quota_limit": String(localized: "\(bot)'s AI provider account has reached its usage limit. Asking again won't help."),
            "context_overflow": String(localized: "\(bot)'s chat is too long to continue. Asking again won't help."),
            "missing_config": String(localized: "\(bot) has no AI provider set up. Asking again won't help."),
            "model_unavailable": String(localized: "\(bot)'s model isn't available. Pick another model for it; asking again won't help."),
            "agent_blocked": String(localized: "\(bot) isn't taking messages. Asking again won't help."),
            "target_scope_unresolved": String(localized: "Hermes couldn't load \(bot)'s settings. Asking again won't help."),
        ]
        return isUnconfirmed ? nil : reason.flatMap { sentences[$0] }
    }
}

extension Transcript {
    var visible: Transcript {
        let log = { (turn: Turn) in
            turn.work + (turn.reply.isEmpty ? [] : [WorkItem(id: "\(turn.id)-reply", kind: .note(turn.reply), startedAt: turn.finishedAt ?? turn.startedAt)])
        }
        var shown: [Turn] = []
        var awaited: [(handle: String, origin: Turn.ID)] = []
        var answered: [(handle: String, at: Int)] = []
        var exchanges: [Turn.ID: Int] = [:]
        for (position, turn) in turns.enumerated() {
            if let message = turn.agentMessage {
                if let index = awaited.firstIndex(where: { $0.handle == message.handle }) {
                    answered.append((awaited.remove(at: index).handle, position))
                    var reply = turn
                    reply.prompt = nil
                    reply.agentMessage = nil
                    shown.append(reply)
                    continue
                }
                exchanges[turn.id] = shown.count
                var exchange = turn
                exchange.prompt = nil
                exchange.reply = ""
                exchange.work = [WorkItem(id: "\(turn.id)-message", kind: .note(message.body.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")), startedAt: turn.startedAt)] + log(turn)
                shown.append(exchange)
                continue
            }
            guard let delivery = turn.delivery else {
                if turn.prompt != nil { awaited += turn.work.compactMap { $0.messagedHandle.map { ($0, turn.id) } } }
                shown.append(turn)
                continue
            }
            let originIndex = turns.indices.last { index in
                turns[index].work.contains { item in if case .tool(let call) = item.kind { call.name == "message_agent" && call.result?.contains(delivery) == true } else { false } }
            }
            let origin = originIndex.map { turns[$0] }
            let handle = origin?.work.first { item in if case .tool(let call) = item.kind { call.result?.contains(delivery) == true } else { false } }?.messagedHandle
            let repliedLater = turn.deliveryFailure?.isUnconfirmed == true && handle != nil && turns[(position + 1)...].contains { $0.agentMessage?.handle == handle }
            if !repliedLater { awaited.removeAll { $0.origin == origin?.id } }
            var followUp = turn
            followUp.deliveryFailure?.target = handle
            if let origin, let index = exchanges[origin.id] {
                shown[index].work += log(turn)
                shown[index].finishedAt = turn.finishedAt
                shown[index].deliveryFailure = shown[index].deliveryFailure ?? followUp.deliveryFailure
                if shown[index].status == .complete {
                    shown[index].status = turn.status
                    shown[index].failure = turn.failure
                }
            } else if turn.deliveryFailure?.isUnconfirmed != false, let originIndex, let index = answered.firstIndex(where: { $0.handle == handle && $0.at > originIndex }) {
                answered.remove(at: index)
            } else if !repliedLater, origin.map({ $0.agentMessage == nil }) ?? turns.contains(where: { $0.agentMessage == nil && $0.prompt != nil }) {
                shown.append(followUp)
            }
        }
        return Transcript(turns: shown + waiting)
    }

    var preview: LastMessage? {
        guard let turn = visible.turns.last(where: { $0.pending == nil && (!$0.reply.isEmpty || $0.prompt?.text.isEmpty == false || $0.agentMessage != nil) }) else { return nil }
        let text = turn.agentMessage.map { String(localized: "Message from \($0.sender)") } ?? (turn.reply.isEmpty ? turn.prompt?.text ?? "" : turn.reply)
        return LastMessage(text: text.split(whereSeparator: \.isWhitespace).joined(separator: " "), date: turn.finishedAt ?? turn.prompt?.sentAt ?? turn.startedAt)
    }

    init(history rows: [HistoryRow]) {
        self.init()
        for row in rows.sorted(by: { $0.id < $1.id }) {
            let date = Date(timeIntervalSince1970: row.timestamp)
            let text = row.displayContent ?? row.content ?? ""
            if row.role == "user", row.displayKind == "steer", !turns.isEmpty {
                closeThinking(at: date)
                turns.append(Turn(id: String(row.id), prompt: Prompt(text: text, sentAt: date), status: .complete, startedAt: date, finishedAt: date, isSteer: true))
                continue
            }
            if row.role == "user" {
                let delivery = deliveryProcess(in: text)
                let notice = delivery == nil ? noticeText(kind: row.displayKind, content: text) : nil
                let prompt = notice == nil && delivery == nil && row.displayKind != "hidden" ? Prompt(raw: text, sentAt: date) : nil
                let hiddenText = row.displayKind == "hidden" ? row.content ?? text : nil
                turns.append(Turn(id: String(row.id), prompt: prompt, notice: notice, agentMessage: AgentMessage(text), delivery: delivery, deliveryFailure: DeliveryFailure(notice: text), hiddenText: hiddenText, status: .complete, startedAt: date, finishedAt: date))
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

    mutating func keepFailures(from old: Transcript) {
        for index in turns.indices {
            guard let failed = old.turns.first(where: { $0.id == turns[index].id && $0.status != .complete }) else { continue }
            turns[index].status = failed.status
            turns[index].failure = failed.failure
        }
        guard let last = old.turns.last, last.status == .error, !turns.contains(where: { $0.id == last.id }) else { return }
        turns.append(last)
    }

    mutating func wait(_ prompt: Prompt, as pending: Turn.Pending, id: String = UUID().uuidString) {
        let turn = Turn(id: id, prompt: prompt, status: .complete, startedAt: prompt.sentAt, pending: pending)
        guard pending != .queued else { return waiting.append(turn) }
        waiting.insert(turn, at: waiting.firstIndex { $0.pending == .queued } ?? waiting.endIndex)
    }

    mutating func dropWaiting(where shouldDrop: (Turn) -> Bool = { _ in true }) -> [String] {
        let dropped = waiting.filter(shouldDrop)
        waiting.removeAll(where: shouldDrop)
        return dropped.compactMap(\.prompt?.text)
    }

    mutating func dequeue() -> Prompt? {
        guard !waiting.contains(where: { $0.pending != .queued }), let index = waiting.firstIndex(where: { $0.pending == .queued }) else { return nil }
        return waiting.remove(at: index).prompt
    }

    mutating func takeSteers(at date: Date = .now) {
        let taken = waiting.filter { $0.pending == .taken }
        guard let first = taken.first, let index = turns.indices.last, turns[index].status == .streaming else { return }
        waiting.removeAll { $0.pending == .taken }
        closeThinking(at: date)
        turns[index].status = .complete
        turns[index].finishedAt = date
        let text = taken.compactMap(\.prompt?.text).joined(separator: "\n")
        turns.append(Turn(id: first.id, prompt: Prompt(text: text, sentAt: first.startedAt), status: .streaming, startedAt: date, isSteer: true))
    }

    private mutating func narrate(_ text: String, id: String, at date: Date) {
        let index = turns.count - 1
        let ranTool = turns[index].work.contains { if case .tool = $0.kind { true } else { false } }
        guard !turns[index].isSteer || turns[index].answer != nil || ranTool else { return turns[index].answer = text }
        appendWork(.note(text), id: id, at: date)
    }

    mutating func begin(prompt text: String, attachments: [Attachment] = [], id: String = UUID().uuidString, at date: Date = .now) {
        turns.append(Turn(id: id, prompt: Prompt(text: text, sentAt: date, attachments: attachments), status: .streaming, startedAt: date))
    }

    mutating func begin(remote user: String, displayKind: String?, at date: Date) {
        waiting.removeAll { $0.pending != .queued }
        let delivery = deliveryProcess(in: user)
        let notice = delivery == nil ? noticeText(kind: displayKind, content: user) : nil
        let prompt = Prompt(raw: user, sentAt: date)
        let isShown = notice == nil && delivery == nil && displayKind != "hidden" && (!prompt.text.isEmpty || !prompt.attachments.isEmpty)
        turns.append(Turn(id: UUID().uuidString, prompt: isShown ? prompt : nil, notice: notice, agentMessage: AgentMessage(user), delivery: delivery, deliveryFailure: DeliveryFailure(notice: user), hiddenText: displayKind == "hidden" ? user : nil, status: .streaming, startedAt: date))
    }

    mutating func apply(_ event: TurnEvent, at date: Date = .now) {
        if case .messageStart = event {
            if turns.last?.status != .streaming {
                waiting.removeAll { $0.pending != .queued }
                turns.append(Turn(id: UUID().uuidString, status: .streaming, startedAt: date))
            }
            return
        }
        let isTool = if case .toolStart = event { true } else if case .toolComplete = event { true } else { false }
        if !isTool { takeSteers(at: date) }
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
            let narration = turns[index].work.compactMap { if case .note(let note) = $0.kind { note } else { nil } } + [turns[index].answer].compactMap(\.self)
            guard !narration.contains(text), narration.joined(separator: "\n") != text, narration.joined(separator: "\n\n") != text else { return }
            appendWork(.thinking(text), id: UUID().uuidString, at: date)
            return
        }
        if case .interim(let text) = event {
            turns[index].reply = ""
            if turns[index].work.last?.kind != .note(text), turns[index].answer != text {
                narrate(text, id: UUID().uuidString, at: date)
            }
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
            let batchDone = !turns[index].work.contains { if case .tool(let call) = $0.kind { call.status == .running } else { false } }
            for item in waiting.indices where batchDone && waiting[item].pending == .steer { waiting[item].pending = .taken }
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
        let reasoning = row.displayCommentary == nil ? row.reasoning ?? row.reasoningContent : row.displayReasoning
        if let reasoning, !reasoning.isEmpty {
            appendWork(.thinking(reasoning), id: "\(row.id)-thinking", at: date)
        }
        for (offset, text) in (row.displayCommentary ?? []).enumerated() where !text.isEmpty {
            narrate(text, id: "\(row.id)-commentary-\(offset)", at: date)
        }
        let content = row.content ?? ""
        if let calls = row.toolCalls, !calls.isEmpty {
            if !content.isEmpty { narrate(content, id: "\(row.id)-note", at: date) }
            for call in calls {
                let (name, arguments) = call.tool
                let tool = ToolCall(name: name, subject: toolSubject(arguments: arguments), arguments: arguments, status: .success)
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
        let closing = "</untrusted_tool_result>"
        let isUntrusted = ["browser_", "web_", "mcp_"].contains { call.name.hasPrefix($0) }
        let body: String
        if isUntrusted, result.hasPrefix("<untrusted_tool_result source=\"\(call.name)\">\n"), result.hasSuffix(closing), let notice = result.range(of: "\n\n") {
            let inner = result[notice.upperBound...].dropLast(closing.count)
            body = String(inner.hasSuffix("\n") ? inner.dropLast() : inner)
        } else {
            body = result
        }
        call.result = body
        call.outcome = summary
        call.status = toolStatus(result: body)
        turns[index].work[workIndex].kind = .tool(call)
        turns[index].work[workIndex].duration = duration ?? date.timeIntervalSince(turns[index].work[workIndex].startedAt)
    }

    private mutating func sealReplyAsNote(at date: Date) {
        guard let index = turns.indices.last, !turns[index].reply.isEmpty else { return }
        narrate(turns[index].reply, id: UUID().uuidString, at: date)
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
