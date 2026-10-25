import Foundation

actor Gateway {
    nonisolated let server: URL
    private let urlSession: URLSession
    private let mintTicket: @Sendable () async throws -> String
    private let statusBroadcast = Broadcast<GatewayStatus>()
    private let eventBroadcast = Broadcast<GatewayEvent>()
    private let requestBroadcast = Broadcast<ServerRequest>()
    private var loop: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var nextID = 1
    private var lastFrameAt = ContinuousClock.now
    private var failures = 0
    private var ticketInSubprotocol = false
    private(set) var status = GatewayStatus.idle

    init(server: URL, urlSession: URLSession, mintTicket: @escaping @Sendable () async throws -> String) {
        self.server = server
        self.urlSession = urlSession
        self.mintTicket = mintTicket
    }

    nonisolated func statuses() -> AsyncStream<GatewayStatus> { statusBroadcast.stream() }
    nonisolated func events() -> AsyncStream<GatewayEvent> { eventBroadcast.stream() }
    nonisolated func serverRequests() -> AsyncStream<ServerRequest> { requestBroadcast.stream() }

    func connect() {
        guard loop == nil else { return }
        loop = Task { await run() }
    }

    func reconnect() {
        disconnect()
        connect()
    }

    func disconnect() {
        loop?.cancel()
        loop = nil
        failures = 0
        teardown()
        publish(.idle)
    }

    func call<Params: Encodable & Sendable, Result: Decodable & Sendable>(_ method: String, _ params: Params, as type: Result.Type = Result.self, timeout: Duration = .seconds(30)) async throws -> Result {
        guard let socket else { throw GatewayError.notConnected }
        let id = nextID
        nextID += 1
        let frame = try JSONEncoder().encode(RPCRequest(id: id, method: method, params: params))
        Task { await send(frame, on: socket, awaitingReplyTo: id, timeout: timeout) }
        let reply = try await withCheckedThrowingContinuation { pending[id] = $0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(RPCReply<Result>.self, from: reply).result
    }

    func reply(to request: ServerRequest, with result: some Encodable & Sendable) async throws {
        guard let socket else { throw GatewayError.notConnected }
        let frame = try JSONEncoder().encode(RPCResponse(id: request.id, result: result))
        try await socket.send(.string(String(decoding: frame, as: UTF8.self)))
    }

    func decline(_ request: ServerRequest, code: Int = -32601, message: String = "not supported") async throws {
        guard let socket else { throw GatewayError.notConnected }
        let frame = try JSONEncoder().encode(RPCErrorResponse(id: request.id, error: RPCError(code: code, message: message)))
        try await socket.send(.string(String(decoding: frame, as: UTF8.self)))
    }

    func eventsSince(_ session: RuntimeSessionID, after seq: Int) async throws -> EventReplay {
        try await call("session.events.since", EventsSinceParams(sessionID: session, lastSeen: seq), as: EventReplay.self)
    }

    private func run() async {
        while !Task.isCancelled {
            publish(.connecting)
            do {
                try await serve()
            } catch let error as HermesError {
                guard !Task.isCancelled else { return }
                switch error {
                case .unauthorized, .identityChanged, .unsupported:
                    teardown()
                    loop = nil
                    return publish(.stopped(error))
                default: break
                }
            } catch {}
            guard !Task.isCancelled else { return }
            teardown()
            failures += 1
            let delay = Duration.seconds(min(30, 1 << min(failures - 1, 5)))
            publish(.retrying(after: delay))
            try? await Task.sleep(for: delay)
        }
    }

    private func serve() async throws {
        do {
            try await serve(ticketInSubprotocol: ticketInSubprotocol)
        } catch GatewayError.ticketRejected where !ticketInSubprotocol {
            ticketInSubprotocol = true
            teardown()
            try await serve(ticketInSubprotocol: true)
        }
    }

    private func serve(ticketInSubprotocol: Bool) async throws {
        let ticket = try await mintTicket()
        try Task.checkCancellation()
        var components = URLComponents(url: server.appending(path: "api/ws"), resolvingAgainstBaseURL: false)
        components?.scheme = server.scheme == "https" ? "wss" : "ws"
        if !ticketInSubprotocol { components?.queryItems = [URLQueryItem(name: "ticket", value: ticket)] }
        guard let url = components?.url else { throw GatewayError.unexpectedFrame }
        let task = ticketInSubprotocol
            ? urlSession.webSocketTask(with: url, protocols: ["hermes-gateway-v1", "hermes-gateway-ticket.\(ticket)"])
            : urlSession.webSocketTask(with: url)
        task.maximumMessageSize = 16 << 20
        socket = task
        lastFrameAt = .now
        task.resume()
        try await withThrowingDiscardingTaskGroup { group in
            group.addTask { try await self.keepAlive(task) }
            let ready = try await awaitReady(on: task)
            group.addTask { try await self.read(task) }
            _ = try? await call("client.capabilities", ["server_requests": true], as: JSONValue.self)
            try Task.checkCancellation()
            failures = 0
            publish(.connected)
            eventBroadcast.yield(ready)
        }
    }

    private func awaitReady(on task: URLSessionWebSocketTask) async throws -> GatewayEvent {
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            let status = (task.response as? HTTPURLResponse)?.statusCode
            if status == 401 || status == 403 || task.closeCode.rawValue == 4401 { throw GatewayError.ticketRejected }
            throw error
        }
        lastFrameAt = .now
        guard case .string(let text) = message, let ready = try? JSONDecoder().decode(EventFrame.self, from: Data(text.utf8)).params,
              ready.type == "gateway.ready",
              case .object(let payload) = ready.payload, case .string = payload["replay_epoch"]
        else { throw GatewayError.unexpectedFrame }
        return ready
    }

    private func read(_ task: URLSessionWebSocketTask) async throws {
        while true {
            let message = try await task.receive()
            lastFrameAt = .now
            guard case .string(let text) = message else { continue }
            handle(Data(text.utf8))
        }
    }

    private func keepAlive(_ task: URLSessionWebSocketTask) async throws {
        var nextPing = ContinuousClock.now + .seconds(15)
        while true {
            try await Task.sleep(until: min(nextPing, lastFrameAt + .seconds(45)), clock: .continuous)
            if ContinuousClock.now >= lastFrameAt + .seconds(45) {
                task.cancel(with: .goingAway, reason: nil)
                throw GatewayError.silent
            }
            guard ContinuousClock.now >= nextPing else { continue }
            nextPing = .now + .seconds(15)
            let id = nextID
            nextID += 1
            try await task.send(.string(#"{"jsonrpc":"2.0","id":\#(id),"method":"gateway.ping","params":{}}"#))
        }
    }

    private func handle(_ data: Data) {
        let decoder = JSONDecoder()
        guard let frame = try? decoder.decode(Frame.self, from: data) else { return }
        if frame.method == "event", let event = try? decoder.decode(EventFrame.self, from: data).params {
            return eventBroadcast.yield(event)
        }
        if frame.method != nil, case .string = frame.id, let request = try? decoder.decode(ServerRequest.self, from: data) {
            return requestBroadcast.yield(request)
        }
        guard case .number(let id) = frame.id, let continuation = pending.removeValue(forKey: Int(id)) else { return }
        guard let error = frame.error else { return continuation.resume(returning: data) }
        continuation.resume(throwing: GatewayError.rpc(code: error.code, message: error.message))
    }

    private func send(_ frame: Data, on task: URLSessionWebSocketTask, awaitingReplyTo id: Int, timeout: Duration) async {
        do {
            try await task.send(.string(String(decoding: frame, as: UTF8.self)))
            try await Task.sleep(for: timeout)
            pending.removeValue(forKey: id)?.resume(throwing: GatewayError.timedOut)
        } catch {
            pending.removeValue(forKey: id)?.resume(throwing: error)
        }
    }

    private func teardown() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        let interrupted = pending.values
        pending.removeAll()
        for continuation in interrupted { continuation.resume(throwing: GatewayError.disconnected) }
    }

    private func publish(_ status: GatewayStatus) {
        self.status = status
        statusBroadcast.yield(status)
    }
}

nonisolated private struct RPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: Params
}

nonisolated private struct RPCResponse<Result: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let result: Result
}

nonisolated private struct RPCErrorResponse: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let error: RPCError
}

nonisolated private struct RPCError: Codable {
    let code: Int
    let message: String
}

nonisolated private struct RPCReply<Result: Decodable>: Decodable {
    let result: Result
}

nonisolated private struct Frame: Decodable {
    let id: JSONValue?
    let method: String?
    let error: RPCError?
}

nonisolated private struct EventFrame: Decodable {
    let params: GatewayEvent
}

nonisolated private struct EventsSinceParams: Encodable {
    let sessionID: RuntimeSessionID
    let lastSeen: Int

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case lastSeen = "last_seen"
    }
}
