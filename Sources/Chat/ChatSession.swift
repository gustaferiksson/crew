import Foundation
import Observation

nonisolated struct TodoItem: Hashable, Identifiable, Sendable {
    enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
        case cancelled
    }

    let id: String
    let content: String
    let status: Status
}

nonisolated extension TodoItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, content, status
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
        id = (try? container.decode(String.self, forKey: .id)) ?? (try? container.decode(Int.self, forKey: .id)).map(String.init) ?? content
        status = (try? container.decode(String.self, forKey: .status)).flatMap(Status.init(rawValue:)) ?? .pending
    }
}

@Observable
final class ChatSession {
    private(set) var transcript = Transcript()
    private(set) var openRequests: [ServerRequest] = [] {
        didSet { payments = payments.filter { payment in openRequests.contains { $0.id == payment.key } } }
    }
    private(set) var payments: [ServerRequest.ID: PaymentCardState] = [:]
    private(set) var endedPayment: String?
    private(set) var todos: [TodoItem] = []
    var returned: [String] = []
    var dismissedOffer: Turn.ID?
    private(set) var generatingTool: String?
    private(set) var statusLine: String?
    private(set) var failure: String?

    let profile: String
    private let gateway: Gateway
    private let urlSession: URLSession
    private var stored: StoredSessionID?
    private var runtime: RuntimeSessionID?
    private var epoch: String?
    private var appliedSeq = 0
    private var todoRevision = -1
    private var awaitedPayment: String?
    private var syncedPosition: ReadPosition?
    private var serverPosition: ReadPosition?
    private var isSyncing = false

    init(bot: Bot, gateway: Gateway, urlSession: URLSession) {
        self.profile = bot.name
        self.stored = bot.canonicalSession?.id
        self.syncedPosition = bot.canonicalSession?.position
        self.gateway = gateway
        self.urlSession = urlSession
    }

    convenience init(fixture bot: Bot, transcript: Transcript, todos: [TodoItem], urlSession: URLSession = .shared, requests: [ServerRequest] = [], payments: [ServerRequest.ID: PaymentCardState] = [:]) {
        self.init(bot: bot, gateway: Gateway(server: URL(filePath: "/"), urlSession: urlSession) { throw CancellationError() }, urlSession: urlSession)
        self.transcript = transcript
        self.todos = todos
        self.openRequests = requests
        self.payments = payments
    }

    var request: PendingRequest? {
        let pending = openRequests.compactMap(PendingRequest.init)
        return pending.first(where: \.isPayment) ?? pending.first
    }

    var isRunning: Bool {
        transcript.turns.last?.status == .streaming
    }

    func run() async {
        let events = gateway.events()
        let requests = gateway.serverRequests()
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await request in requests { await self.receive(request) }
            }
            group.addTask {
                if await self.gateway.status == .connected { await self.attach() }
                for await event in events { await self.handle(event) }
            }
        }
    }

    func sync(to position: ReadPosition?) {
        serverPosition = position
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            while let position = serverPosition, position != syncedPosition, !isRunning {
                syncedPosition = position
                let shown = transcript
                guard let rows = try? await history(of: StoredSessionID(rawValue: position.session), profile: profile, on: gateway.server, with: urlSession) else {
                    syncedPosition = nil
                    break
                }
                guard transcript == shown else { continue }
                var reloaded = Transcript(history: rows)
                reloaded.adoptIDs(from: shown)
                reloaded.keepFailures(from: shown)
                reloaded.waiting = shown.waiting
                transcript = reloaded
            }
            isSyncing = false
        }
    }

    func send(_ text: String, attachments: [Attachment] = [], mentioning bots: [Bot] = [], mode: SendMode) {
        let prompt = Prompt(text: text.trimmingCharacters(in: .whitespacesAndNewlines), sentAt: .now, attachments: attachments, mentionNote: mentionNote(for: bots))
        guard !prompt.text.isEmpty || !attachments.isEmpty, let runtime else { return }
        guard isRunning else { return submit(prompt) }
        if mode == .queue || !attachments.isEmpty || transcript.turns.last.map({ $0.agentMessage != nil || $0.delivery != nil }) == true { return transcript.wait(prompt, as: .queued) }
        let id = UUID().uuidString
        transcript.wait(prompt, as: .steer, id: id)
        Task {
            do {
                _ = try await gateway.call("session.steer", ["session_id": runtime.rawValue, "text": prompt.text], as: JSONValue.self)
            } catch {
                returned += transcript.dropWaiting { $0.id == id }
                failure = error.localizedDescription
            }
        }
    }

    func unqueue(_ id: Turn.ID) {
        returned += transcript.dropWaiting { $0.id == id }
    }

    func sendHidden(_ text: String) {
        guard let runtime, !isRunning else { return }
        transcript.begin(remote: text, displayKind: "hidden", at: .now)
        Task {
            do {
                _ = try await gateway.call("prompt.submit", ["session_id": runtime.rawValue, "text": text, "display_kind": "hidden"], as: JSONValue.self)
            } catch {
                transcript.apply(.messageComplete(text: "", status: .error, error: error.localizedDescription))
            }
        }
    }

    func stop() {
        guard let runtime else { return }
        returned += transcript.dropWaiting { $0.pending != .taken }
        Task {
            do {
                _ = try await gateway.call("session.interrupt", ["session_id": runtime.rawValue], as: JSONValue.self)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    func respond(to id: ApprovalRequest.ID, with choice: ApprovalChoice) {
        guard let request = openRequests.first(where: { $0.id == id }), case .approval(let approval) = PendingRequest(request), approval.isPayment else {
            return reply(to: id, with: ["choice": choice.rawValue])
        }
        guard choice == .deny || choice == .once else { return }
        guard let runtime, let requestID = approval.requestID else {
            return choice == .deny ? reply(to: id, with: ["choice": choice.rawValue]) : ()
        }
        if choice == .deny {
            openRequests.removeAll { $0.id == id }
        } else {
            payments[id]?.isApproved = true
        }
        payments[id]?.failure = nil
        Task {
            do {
                let reply = try await gateway.call("approval.respond", ApprovalRespondParams(sessionID: runtime, choice: choice.rawValue, requestID: requestID), as: ApprovalRespondReply.self)
                if choice == .once, reply.resolved == 0 {
                    let details = try? await paymentsCall("payments/requests/\(requestID)", on: gateway.server, with: urlSession, as: PaymentDetails.self)
                    if details?.state != .approved { payments[id]?.isApproved = false }
                }
                if choice == .once, payments[id]?.isApproved == true { try? await Task.sleep(for: .seconds(0.8)) }
                openRequests.removeAll { $0.id == id }
            } catch GatewayError.rpc(code: 4001, _) {
                openRequests.removeAll { $0.id == id }
            } catch {
                if !openRequests.contains(where: { $0.id == id }) { openRequests.insert(request, at: 0) }
                payments[id, default: PaymentCardState()].isApproved = false
                payments[id]?.failure = String(localized: "Couldn't reach Hermes. Try again.")
                if payments[id]?.lookup == .loading { lookUp(request) }
            }
        }
    }

    func retryPayment(_ id: ApprovalRequest.ID) {
        guard let request = openRequests.first(where: { $0.id == id }) else { return }
        lookUp(request)
    }

    func expirePayment(_ id: ApprovalRequest.ID) {
        openRequests.removeAll { $0.id == id }
    }

    func expectPayment(_ requestID: String) {
        awaitedPayment = requestID
        endedPayment = nil
        guard runtime != nil else { return }
        Task { await checkAwaitedPayment() }
    }

    func dismissEndedPayment() {
        endedPayment = nil
    }

    private func lookUp(_ request: ServerRequest) {
        guard case .approval(let approval) = PendingRequest(request) else { return }
        payments[request.id, default: PaymentCardState()].lookup = .loading
        Task {
            let lookup = await lookUpPayment(approval, on: gateway.server, with: urlSession)
            guard openRequests.contains(where: { $0.id == request.id }) else { return }
            payments[request.id, default: PaymentCardState()].lookup = lookup
        }
    }

    private func checkAwaitedPayment() async {
        guard let requestID = awaitedPayment else { return }
        awaitedPayment = nil
        let isOpen = openRequests.contains { request in
            guard case .approval(let approval) = PendingRequest(request) else { return false }
            return approval.requestID == requestID
        }
        guard !isOpen, let details = try? await paymentsCall("payments/requests/\(requestID)", on: gateway.server, with: urlSession, as: PaymentDetails.self) else { return }
        endedPayment = endedPaymentNotice(details)
    }

    func answer(_ id: QuestionRequest.ID, with answers: [String: String]) {
        reply(to: id, with: answers.isEmpty ? [:] : ["answers": answers])
    }

    private func reply(to id: String, with result: some Encodable & Sendable) {
        guard let request = openRequests.first(where: { $0.id == id }) else { return }
        openRequests.removeAll { $0.id == id }
        Task {
            do {
                try await gateway.reply(to: request, with: result)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    func download(_ attachment: Attachment) async throws -> Data {
        if let data = attachment.data { return data }
        guard let path = attachment.path else { throw HermesError.invalidResponse }
        var request = hermesRequest("api/fs/download", on: gateway.server)
        request.url?.append(queryItems: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "profile", value: profile),
        ] + (stored.map { [URLQueryItem(name: "session_id", value: $0.rawValue)] } ?? []))
        let (data, response) = try await urlSession.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw HermesError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    func completePath(_ word: String) async -> [PathCompletion] {
        guard let runtime else { return [] }
        return (try? await gateway.call("complete.path", ["session_id": runtime.rawValue, "word": word], as: PathCompletions.self).items) ?? []
    }

    private func submit(_ prompt: Prompt) {
        guard let runtime else { return }
        transcript.begin(prompt: prompt.text, attachments: prompt.attachments)
        Task {
            var staged: [String] = []
            do {
                var references: [String] = []
                for attachment in prompt.attachments {
                    guard let data = attachment.data else { continue }
                    if attachment.kind == .image {
                        let params = ["session_id": runtime.rawValue, "content_base64": data.base64EncodedString(), "filename": attachment.name]
                        staged.append(try await gateway.call("image.attach_bytes", params, as: AttachResult.self).path)
                    } else {
                        let params = ["session_id": runtime.rawValue, "data_url": "data:\(attachment.mimeType);base64,\(data.base64EncodedString())", "name": attachment.name]
                        references.append(try await gateway.call("file.attach", params, as: AttachResult.self).refText ?? "")
                    }
                }
                let message = [references.joined(separator: "\n"), prompt.text + prompt.mentionNote].filter { !$0.isEmpty }.joined(separator: "\n\n")
                _ = try await gateway.call("prompt.submit", ["session_id": runtime.rawValue, "text": message.isEmpty ? imageOnlyPrompt : message], as: JSONValue.self)
            } catch {
                for path in staged {
                    _ = try? await gateway.call("image.detach", ["session_id": runtime.rawValue, "path": path], as: JSONValue.self)
                }
                transcript.apply(.messageComplete(text: "", status: .error, error: error.localizedDescription))
            }
        }
    }

    private func attach() async {
        do {
            if stored == nil {
                stored = try await gateway.call("session.list", ListParams(profile: profile), as: StoredSessions.self).sessions.first?.id
            }
            let snapshot = if let stored {
                try await gateway.call("session.resume", ResumeParams(sessionID: stored, profile: profile), as: LiveSnapshot.self)
            } else {
                try await gateway.call("session.create", CreateParams(profile: profile), as: LiveSnapshot.self)
            }
            if stored == nil {
                // session.create writes no row until the first prompt; a reaped runtime then resumes the key as an untitled, visible row.
                _ = try await gateway.call("session.title", ["session_id": snapshot.sessionID.rawValue, "title": "Bot Chat"], as: JSONValue.self)
            }
            try await load(snapshot)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func reattach(epoch newEpoch: String?) async {
        guard let runtime, let stored, newEpoch == epoch else { return await attach() }
        do {
            let snapshot = try await gateway.call("session.resume", ResumeParams(sessionID: stored, profile: profile), as: LiveSnapshot.self)
            let replay = snapshot.sessionID == runtime ? try await gateway.eventsSince(runtime, after: appliedSeq) : nil
            guard let replay, !replay.truncated, !replay.events.contains(where: { $0.type == "message.start" }) else { return try await load(snapshot) }
            for event in replay.events { apply(event) }
            if isRunning, snapshot.running != true { return try await load(snapshot) }
            for request in replay.openRequests { await receive(request) }
        } catch {
            failure = error.localizedDescription
        }
    }

    private func load(_ snapshot: LiveSnapshot) async throws {
        let stored = snapshot.storedSessionID ?? stored
        let rows = if let stored, snapshot.messageCount != 0 {
            try await history(of: stored, profile: profile, on: gateway.server, with: urlSession)
        } else {
            [HistoryRow]()
        }
        let replay = try await gateway.eventsSince(snapshot.sessionID, after: 0)
        var transcript = Transcript(history: rows)
        if snapshot.running == true {
            let startedAt = snapshot.turnStartedAt.map(Date.init(timeIntervalSince1970:)) ?? .now
            let user = snapshot.inflight?.user ?? ""
            if !user.isEmpty, transcript.turns.last?.prompt?.text == Prompt(raw: user, sentAt: startedAt).text { transcript.turns.removeLast() }
            transcript.begin(remote: user, displayKind: snapshot.inflight?.displayKind, at: startedAt)
        }
        let previous = self.transcript
        transcript.waiting = previous.waiting.filter { waiting in
            guard waiting.pending != .queued else { return true }
            let text = waiting.prompt?.text ?? ""
            return snapshot.running == true && !transcript.turns.contains { $0.startedAt >= waiting.startedAt.addingTimeInterval(-1) && $0.prompt?.text.contains(text) == true }
        }
        self.stored = stored
        self.transcript = transcript
        runtime = snapshot.sessionID
        epoch = replay.epoch
        appliedSeq = 0
        todos = snapshot.todoState?.todos ?? []
        todoRevision = snapshot.todoState?.revision ?? -1
        generatingTool = nil
        statusLine = nil
        failure = nil
        if snapshot.running == true {
            if let start = replay.events.lastIndex(where: { $0.type == "message.start" }) {
                for event in replay.events[start...] { apply(event) }
            } else {
                self.transcript.apply(.messageDelta(snapshot.inflight?.assistant ?? ""))
                for event in replay.events where event.type == "message.complete" { apply(event) }
            }
        }
        self.transcript.adoptIDs(from: previous)
        if !isRunning, let next = self.transcript.dequeue() { submit(next) }
        appliedSeq = max(appliedSeq, replay.latestSeq)
        let incoming = (snapshot.openRequests ?? []) + replay.openRequests
        openRequests.removeAll { request in request.sessionID != snapshot.sessionID || !incoming.contains { $0.id == request.id } }
        for request in incoming { await receive(request) }
        await checkAwaitedPayment()
    }

    private func receive(_ request: ServerRequest) async {
        guard let runtime, request.sessionID == runtime, !openRequests.contains(where: { $0.id == request.id }) else { return }
        guard PendingRequest(request) != nil else {
            try? await gateway.decline(request, code: 4404, message: "Crew can't show this request.")
            return
        }
        openRequests.append(request)
        if PendingRequest(request)?.isPayment == true { lookUp(request) }
    }

    private func handle(_ event: GatewayEvent) async {
        if event.type == "gateway.ready" {
            let epoch: String? = if case .object(let payload) = event.payload, case .string(let value) = payload["replay_epoch"] { value } else { nil }
            return await reattach(epoch: epoch)
        }
        guard let runtime, event.sessionID == runtime else { return }
        await ingest(event)
    }

    private func ingest(_ event: GatewayEvent) async {
        guard event.type == "message.start", !isRunning, let runtime, let seq = event.seq, seq > appliedSeq else { return apply(event) }
        let snapshot = try? await gateway.call("session.activate", ActivateParams(sessionID: runtime), as: LiveSnapshot.self)
        guard !isRunning, runtime == self.runtime, seq > appliedSeq else { return apply(event) }
        appliedSeq = seq
        let startedAt = snapshot?.turnStartedAt.map(Date.init(timeIntervalSince1970:)) ?? .now
        transcript.begin(remote: snapshot?.inflight?.user ?? "", displayKind: snapshot?.inflight?.displayKind, at: startedAt)
    }

    func apply(_ event: GatewayEvent) {
        if let seq = event.seq {
            guard seq > appliedSeq else { return }
            appliedSeq = seq
        }
        let payload = (try? JSONDecoder().decode(EventPayload.self, from: JSONEncoder().encode(event.payload))) ?? EventPayload()
        if let todos = payload.todos, payload.revision ?? .max >= todoRevision {
            self.todos = todos
            todoRevision = payload.revision ?? todoRevision
        }
        let type = event.type
        if type == "message.start" { return transcript.apply(.messageStart) }
        if type == "thinking.delta" { return transcript.takeSteers() }
        if type == "message.delta" { return transcript.apply(.messageDelta(payload.text ?? "")) }
        if type == "reasoning.delta" { return transcript.apply(.reasoningDelta(payload.text ?? "")) }
        if type == "reasoning.available" { return transcript.apply(.reasoningAvailable(payload.text ?? "")) }
        if type == "message.interim" { return transcript.apply(.interim(payload.text ?? "")) }
        if type == "status.update" {
            // Hermes prefixes its informational diagnostics with ℹ (U+2139).
            guard payload.text?.unicodeScalars.first != "\u{2139}" else { return }
            statusLine = payload.text
            return
        }
        if type == "tool.generating" {
            generatingTool = payload.name
            return
        }
        if type == "tool.start", let id = payload.toolID {
            generatingTool = nil
            return transcript.apply(.toolStart(id: id, name: payload.name ?? "tool", context: payload.context, arguments: payload.arguments ?? ""))
        }
        if type == "tool.complete", let id = payload.toolID {
            let isVault = transcript.turns.last?.work.contains { item in
                guard item.id == id, case .tool(let call) = item.kind else { return false }
                return call.name == "browser_vault"
            } ?? false
            if isVault { openRequests.removeAll { PendingRequest($0)?.isPayment == true } }
            return transcript.apply(.toolComplete(id: id, duration: payload.duration, summary: payload.summary, result: payload.result ?? ""))
        }
        if type == "message.complete" {
            let hasThinking = transcript.turns.last?.work.contains { if case .thinking = $0.kind { true } else { false } } ?? false
            if let reasoning = payload.reasoning, !reasoning.isEmpty, !hasThinking {
                transcript.apply(.reasoningAvailable(reasoning))
            }
            let status = payload.status.flatMap(Turn.Status.init(rawValue:)) ?? .complete
            transcript.apply(.messageComplete(text: payload.text ?? "", status: status, error: payload.error ?? payload.failureReason))
            openRequests.removeAll { PendingRequest($0)?.isPayment == true }
            generatingTool = nil
            statusLine = nil
            sync(to: serverPosition)
            if status != .complete { returned += transcript.dropWaiting { $0.pending == .steer } }
            guard let next = transcript.dequeue() else { return }
            return submit(next)
        }
        if type == "error" {
            failure = payload.message
            guard isRunning else { return }
            return transcript.apply(.messageComplete(text: "", status: .error, error: payload.message))
        }
        if type == "request.cancel" {
            openRequests.removeAll { $0.id == payload.id }
            return
        }
        if type == "approval.cancelled" {
            let cancelled = payload.requestIDs ?? []
            openRequests.removeAll { request in
                guard case .object(let params) = request.params, case .string(let id) = params["request_id"] else { return false }
                return cancelled.contains(id)
            }
        }
    }
}

extension PendingRequest {
    nonisolated init?(_ request: ServerRequest) {
        guard let data = try? JSONEncoder().encode(request.params) else { return nil }
        if request.method == "approval", let params = try? JSONDecoder().decode(ApprovalParams.self, from: data) {
            self = .approval(ApprovalRequest(
                id: request.id,
                command: params.command ?? "",
                description: params.description ?? "",
                toolName: params.toolName,
                choices: (params.choices ?? []).compactMap(ApprovalChoice.init(rawValue:)),
                requestID: params.requestID
            ))
            return
        }
        if request.method == "clarify", let params = try? JSONDecoder().decode(ClarifyParams.self, from: data) {
            self = .question(QuestionRequest(id: request.id, questions: params.questions.map {
                QuestionRequest.Question(id: $0.qid, text: $0.question, choices: $0.choices ?? [], isMultiSelect: $0.multiSelect ?? false)
            }))
            return
        }
        return nil
    }
}

nonisolated struct ApprovalParams: Decodable, Sendable {
    let command: String?
    let description: String?
    let choices: [String]?
    let toolName: String?
    let requestID: String?

    private enum CodingKeys: String, CodingKey {
        case command, description, choices
        case toolName = "tool_name"
        case requestID = "request_id"
    }
}

nonisolated private struct ApprovalRespondReply: Decodable, Sendable {
    let resolved: Int?
}

nonisolated private struct ApprovalRespondParams: Encodable, Sendable {
    let sessionID: RuntimeSessionID
    let choice: String
    let requestID: String

    private enum CodingKeys: String, CodingKey {
        case choice
        case sessionID = "session_id"
        case requestID = "request_id"
    }
}

nonisolated private struct ClarifyParams: Decodable {
    struct Question: Decodable {
        let qid: String
        let question: String
        let choices: [String]?
        let multiSelect: Bool?

        private enum CodingKeys: String, CodingKey {
            case qid, question, choices
            case multiSelect = "multi_select"
        }
    }

    let questions: [Question]
}

nonisolated private struct ListParams: Encodable, Sendable {
    let profile: String
    let title = "Bot Chat"
    let includeHidden = true

    private enum CodingKeys: String, CodingKey {
        case profile, title
        case includeHidden = "include_hidden"
    }
}

nonisolated private struct CreateParams: Encodable, Sendable {
    let profile: String
    let title = "Bot Chat"
    let hidden = true
    let followProfileConfig = true

    private enum CodingKeys: String, CodingKey {
        case profile, title, hidden
        case followProfileConfig = "follow_profile_config"
    }
}

nonisolated private struct ResumeParams: Encodable, Sendable {
    let sessionID: StoredSessionID
    let profile: String
    let omitMessages = true
    let inlineImages = false

    private enum CodingKeys: String, CodingKey {
        case profile
        case sessionID = "session_id"
        case omitMessages = "omit_messages"
        case inlineImages = "inline_images"
    }
}

nonisolated private struct ActivateParams: Encodable, Sendable {
    let sessionID: RuntimeSessionID
    let omitMessages = true

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case omitMessages = "omit_messages"
    }
}

nonisolated private struct AttachResult: Decodable, Sendable {
    let path: String
    let refText: String?

    private enum CodingKeys: String, CodingKey {
        case path
        case refText = "ref_text"
    }
}

nonisolated private struct StoredSessions: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        let id: StoredSessionID
    }

    let sessions: [Row]
}

nonisolated private struct PathCompletions: Decodable, Sendable {
    let items: [PathCompletion]
}

nonisolated private struct HistoryPage: Decodable, Sendable {
    let messages: [HistoryRow]
}

nonisolated func history(of stored: StoredSessionID, profile: String, on server: URL, with urlSession: URLSession, limit: Int = 500) async throws -> [HistoryRow] {
    try await fetch(historyRequest(of: stored, profile: profile, on: server, limit: limit), with: urlSession, as: HistoryPage.self).messages
}

nonisolated func historyRequest(of stored: StoredSessionID, profile: String, on server: URL, limit: Int) -> URLRequest {
    var request = hermesRequest("api/sessions/\(stored.rawValue)/messages", on: server)
    request.url?.append(queryItems: [
        URLQueryItem(name: "profile", value: profile),
        URLQueryItem(name: "order", value: "latest"),
        URLQueryItem(name: "limit", value: String(limit)),
        URLQueryItem(name: "include_compacted", value: "true"),
        URLQueryItem(name: "inline_images", value: "false"),
    ])
    return request
}

nonisolated private struct LiveSnapshot: Decodable, Sendable {
    struct Inflight: Decodable, Sendable {
        let user: String?
        let assistant: String?
        let displayKind: String?

        private enum CodingKeys: String, CodingKey {
            case user, assistant
            case displayKind = "display_kind"
        }
    }

    struct TodoState: Decodable, Sendable {
        let todos: [TodoItem]
        let revision: Int
    }

    let sessionID: RuntimeSessionID
    let storedSessionID: StoredSessionID?
    let messageCount: Int?
    let running: Bool?
    let turnStartedAt: Double?
    let inflight: Inflight?
    let todoState: TodoState?
    let openRequests: [ServerRequest]?

    private enum CodingKeys: String, CodingKey {
        case running, inflight
        case sessionID = "session_id"
        case storedSessionID = "stored_session_id"
        case messageCount = "message_count"
        case turnStartedAt = "turn_started_at"
        case todoState = "todo_state"
        case openRequests = "open_requests"
    }
}

nonisolated private struct EventPayload: Sendable {
    var text: String?
    var message: String?
    var name: String?
    var toolID: String?
    var context: String?
    var arguments: String?
    var result: String?
    var summary: String?
    var duration: TimeInterval?
    var todos: [TodoItem]?
    var revision: Int?
    var status: String?
    var error: String?
    var failureReason: String?
    var reasoning: String?
    var id: String?
    var requestIDs: [String]?
}

nonisolated extension EventPayload: Decodable {
    private enum CodingKeys: String, CodingKey {
        case text, message, name, context, args, result, summary, todos, revision, status, error, reasoning, id
        case toolID = "tool_id"
        case argsText = "args_text"
        case resultText = "result_text"
        case duration = "duration_s"
        case failureReason = "failure_reason"
        case requestIDs = "request_ids"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let args = try? container.decodeIfPresent(JSONValue.self, forKey: .args)
        let result = try? container.decodeIfPresent(JSONValue.self, forKey: .result)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        toolID = try? container.decodeIfPresent(String.self, forKey: .toolID)
        context = try? container.decodeIfPresent(String.self, forKey: .context)
        arguments = (try? container.decodeIfPresent(String.self, forKey: .argsText)) ?? args.flatMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        if case .string(let value) = result {
            self.result = value
        } else {
            self.result = result.flatMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? (try? container.decodeIfPresent(String.self, forKey: .resultText))
        }
        summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        duration = try? container.decodeIfPresent(Double.self, forKey: .duration)
        todos = try? container.decodeIfPresent([TodoItem].self, forKey: .todos)
        revision = try? container.decodeIfPresent(Int.self, forKey: .revision)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        failureReason = try? container.decodeIfPresent(String.self, forKey: .failureReason)
        reasoning = try? container.decodeIfPresent(String.self, forKey: .reasoning)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        requestIDs = try? container.decodeIfPresent([String].self, forKey: .requestIDs)
    }
}
