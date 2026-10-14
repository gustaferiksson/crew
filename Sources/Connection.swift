import Foundation
import Network
import Observation

nonisolated struct StoredCookie: Codable, Equatable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    let isSecure: Bool
}

nonisolated struct StoredSession: Codable, Equatable, Sendable {
    let server: URL
    let installID: String
    let cookies: [StoredCookie]
}

@Observable
final class Connection {
    enum State {
        case signedOut, connecting, connected, unreachable
    }

    private(set) var state: State
    private(set) var session: StoredSession?
    private(set) var gateway: Gateway?
    private(set) var signInError: HermesError?

    let urlSession: URLSession
    private let cookieJar: HTTPCookieStorage
    private var statusTask: Task<Void, Never>?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let cookieJar = configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        let session = readKeychain(account: "session").flatMap { try? JSONDecoder().decode(StoredSession.self, from: $0) }
        for cookie in session?.cookies ?? [] {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name, .value: cookie.value, .domain: cookie.domain, .path: cookie.path,
            ]
            properties[.expires] = cookie.expires
            properties[.secure] = cookie.isSecure ? "TRUE" : nil
            HTTPCookie(properties: properties).map(cookieJar.setCookie)
        }
        self.urlSession = URLSession(configuration: configuration)
        self.cookieJar = cookieJar
        self.session = session
        self.state = session == nil ? .signedOut : .connecting
        if let session { startGateway(for: session) }
    }

    init(fixture state: State, server: URL, signInError: HermesError? = nil) {
        self.urlSession = URLSession(configuration: .ephemeral)
        self.cookieJar = HTTPCookieStorage.shared
        self.session = state == .signedOut ? nil : StoredSession(server: server, installID: "fixture", cookies: [])
        self.state = state
        self.signInError = signInError
    }

    func monitorNetwork() async {
        var interfaces: [String]?
        for await path in NWPathMonitor() {
            let previous = interfaces
            interfaces = path.status == .satisfied ? path.availableInterfaces.map(\.name) : nil
            guard let gateway else { continue }
            guard path.status == .satisfied else {
                await gateway.disconnect()
                state = .unreachable
                continue
            }
            guard interfaces != previous else { continue }
            retry()
        }
    }

    func suspend() {
        guard let gateway else { return }
        Task { await gateway.disconnect() }
    }

    func retry() {
        guard let gateway else { return }
        if state != .connected { state = .connecting }
        Task { await gateway.reconnect() }
    }

    func signIn(server input: String, username: String, password: String) async {
        signInError = nil
        do {
            let server = try serverURL(from: input)
            let status = try await probe(server, with: urlSession)
            cookieJar.removeCookies(since: .distantPast)
            let login = hermesRequest("auth/password-login", on: server, json: ["provider": "basic", "username": username, "password": password])
            do {
                _ = try await fetch(login, with: urlSession, as: Empty.self)
            } catch HermesError.unauthorized {
                throw HermesError.badCredentials
            }
            let user: AuthUser = try await fetch(hermesRequest("api/auth/me", on: server), with: urlSession)
            guard user.provider == "basic" else { throw HermesError.unsupported("This server signed you in with \(user.provider), which Crew doesn't support yet.") }
            let cookies = (cookieJar.cookies ?? []).map {
                StoredCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path, expires: $0.expiresDate, isSecure: $0.isSecure)
            }
            let session = StoredSession(server: server, installID: status.installId, cookies: cookies)
            try saveKeychain(JSONEncoder().encode(session), account: "session")
            self.session = session
            state = .connecting
            startGateway(for: session)
            retry()
        } catch {
            signInError = error as? HermesError ?? .invalidResponse
        }
    }

    func signOut() async {
        if let server = session?.server {
            var logout = hermesRequest("auth/logout", on: server, json: [:])
            logout.timeoutInterval = 5
            _ = try? await fetch(logout, with: urlSession, as: Empty.self)
        }
        endSession(nil)
    }

    private func startGateway(for session: StoredSession) {
        let gateway = Gateway(server: session.server, urlSession: urlSession) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.mintTicket()
        }
        let statuses = gateway.statuses()
        statusTask = Task {
            for await status in statuses {
                if status == .connected { state = .connected }
                if status == .connecting, state != .unreachable { state = .connecting }
                if case .retrying = status { state = .unreachable }
                if case .stopped(let error) = status { endSession(error) }
            }
        }
        self.gateway = gateway
    }

    private func mintTicket() async throws -> String {
        guard let session else { throw HermesError.unauthorized }
        let status = try await probe(session.server, with: urlSession)
        guard status.installId == session.installID else { throw HermesError.identityChanged }
        let ticket: WebSocketTicket = try await fetch(hermesRequest("api/auth/ws-ticket", on: session.server, json: [:]), with: urlSession)
        let cookies = (cookieJar.cookies ?? []).map {
            StoredCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path, expires: $0.expiresDate, isSecure: $0.isSecure)
        }
        if cookies != session.cookies, self.session == session {
            let updated = StoredSession(server: session.server, installID: session.installID, cookies: cookies)
            try? saveKeychain(JSONEncoder().encode(updated), account: "session")
            self.session = updated
        }
        return ticket.ticket
    }

    private func endSession(_ error: HermesError?) {
        statusTask?.cancel()
        if let gateway { Task { await gateway.disconnect() } }
        gateway = nil
        deleteKeychain(account: "session")
        cookieJar.removeCookies(since: .distantPast)
        session = nil
        signInError = error
        state = .signedOut
    }
}
