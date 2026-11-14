import Foundation

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

nonisolated func restore(_ cookies: [StoredCookie], into jar: HTTPCookieStorage) {
    for cookie in cookies {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: cookie.name, .value: cookie.value, .domain: cookie.domain, .path: cookie.path,
        ]
        properties[.expires] = cookie.expires
        properties[.secure] = cookie.isSecure ? "TRUE" : nil
        HTTPCookie(properties: properties).map(jar.setCookie)
    }
}

nonisolated func restoredURLSession() -> (session: StoredSession, urlSession: URLSession)? {
    guard let stored = readKeychain(account: "session").flatMap({ try? JSONDecoder().decode(StoredSession.self, from: $0) }) else { return nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    restore(stored.cookies, into: configuration.httpCookieStorage ?? HTTPCookieStorage.shared)
    return (stored, URLSession(configuration: configuration))
}

nonisolated func connectedGateway(to server: URL, with urlSession: URLSession) async -> Gateway? {
    let gateway = Gateway(server: server, urlSession: urlSession) {
        try await fetch(hermesRequest("api/auth/ws-ticket", on: server, json: [:]), with: urlSession, as: WebSocketTicket.self).ticket
    }
    let statuses = gateway.statuses()
    await gateway.connect()
    let isConnected = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await status in statuses {
                if status == .connected { return true }
                if case .stopped = status { return false }
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(15))
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    guard isConnected else {
        await gateway.disconnect()
        return nil
    }
    return gateway
}
