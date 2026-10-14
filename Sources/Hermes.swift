import Foundation

nonisolated struct ServerStatus: Decodable, Sendable {
    let version: String
    let authRequired: Bool
    let authProviders: [String]
    let installId: String
}

nonisolated struct AuthUser: Decodable, Sendable {
    let userId: String
    let provider: String
}

nonisolated struct WebSocketTicket: Decodable, Sendable {
    let ticket: String
}

nonisolated struct Empty: Decodable, Sendable {}

nonisolated struct Transcription: Decodable, Sendable {
    let transcript: String
}

nonisolated enum HermesError: LocalizedError, Equatable {
    case invalidServer
    case unreachable(host: String)
    case unauthorized
    case badCredentials
    case rateLimited
    case unsupported(String)
    case identityChanged
    case keychain(OSStatus)
    case server(Int, detail: String? = nil)
    case invalidResponse

    var errorDescription: String? {
        if case .invalidServer = self { return "Enter a server address like hermes.example.com." }
        if case .unreachable(let host) = self { return "Can't reach \(host). Check your connection or VPN." }
        if case .unauthorized = self { return "Your session expired. Sign in again." }
        if case .badCredentials = self { return "Wrong username or password." }
        if case .rateLimited = self { return "Too many sign-in attempts. Wait a minute and try again." }
        if case .unsupported(let reason) = self { return reason }
        if case .identityChanged = self { return "This server's identity changed since you signed in. Sign in again to trust it." }
        if case .keychain(let status) = self { return "Couldn't save the session to the Keychain (\(status))." }
        if case .server(let code, let detail) = self { return detail ?? "The server answered with an error (\(code))." }
        return "The server sent a response Crew doesn't understand."
    }
}

nonisolated private struct ErrorBody: Decodable {
    let detail: String
}

nonisolated private let unreachableCodes: Set<URLError.Code> = [
    .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
    .networkConnectionLost, .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed,
]

nonisolated func serverURL(from input: String) throws -> URL {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    guard let components, let scheme = components.scheme, ["https", "http"].contains(scheme), let host = components.host, !host.isEmpty,
          let url = URL(string: "\(scheme)://\(host)\(components.port.map { ":\($0)" } ?? "")")
    else { throw HermesError.invalidServer }
    return url
}

nonisolated func hermesRequest(_ path: String, on server: URL, json body: [String: String]? = nil) -> URLRequest {
    var request = URLRequest(url: server.appending(path: path))
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    guard let body else { return request }
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(body)
    return request
}

nonisolated func fetch<Response: Decodable>(_ request: URLRequest, with session: URLSession, as type: Response.Type = Response.self) async throws -> Response {
    let host = request.url?.host() ?? "the server"
    let (data, response): (Data, URLResponse)
    do {
        (data, response) = try await session.data(for: request)
    } catch let error as URLError where unreachableCodes.contains(error.code) {
        throw HermesError.unreachable(host: host)
    }
    guard let http = response as? HTTPURLResponse else { throw HermesError.invalidResponse }
    if http.statusCode == 401 { throw HermesError.unauthorized }
    if http.statusCode == 429 { throw HermesError.rateLimited }
    if [502, 503, 504].contains(http.statusCode) { throw HermesError.unreachable(host: host) }
    guard (200..<300).contains(http.statusCode) else {
        throw HermesError.server(http.statusCode, detail: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
        return try decoder.decode(Response.self, from: data)
    } catch {
        throw HermesError.invalidResponse
    }
}

nonisolated func probe(_ server: URL, with session: URLSession) async throws -> ServerStatus {
    let status: ServerStatus = try await fetch(hermesRequest("api/status", on: server), with: session)
    guard status.authRequired, status.authProviders.contains("basic") else {
        throw HermesError.unsupported("This server doesn't offer username and password sign-in.")
    }
    let version = status.version.prefix { $0 != "+" && $0 != "-" }.split(separator: ".").map { Int($0) ?? 0 }
    guard !version.lexicographicallyPrecedes([0, 21, 3]) else {
        throw HermesError.unsupported("Crew needs Hermes 0.21.3 or newer. This server runs \(status.version).")
    }
    return status
}
