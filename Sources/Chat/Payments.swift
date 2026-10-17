import Foundation

nonisolated let paymentCommandPrefix = "Fill payment card '"

nonisolated struct PaymentCommand: Equatable, Sendable {
    let cardLabel: String
    let origin: String
    let host: String
    let last4: String?

    init?(_ command: String) {
        guard command.hasPrefix(paymentCommandPrefix), let separator = command.range(of: "' on ", options: .backwards) else { return nil }
        let label = String(command[command.index(command.startIndex, offsetBy: paymentCommandPrefix.count)..<separator.lowerBound])
        let origin = command[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URLComponents(string: origin)?.encodedHost?.lowercased(), !host.isEmpty, !label.isEmpty else { return nil }
        self.origin = origin
        self.host = host
        cardLabel = label.hasSuffix(" · \(host)") ? String(label.dropLast(" · \(host)".count)) : label
        last4 = label.firstMatch(of: /•••• ?(\d{4})/).map { String($0.1) }
    }
}

nonisolated func isPunycode(_ host: String) -> Bool {
    host.split(separator: ".").contains { $0.lowercased().hasPrefix("xn--") }
}

nonisolated struct PaymentDetails: Decodable, Equatable, Sendable {
    enum State: String, Decodable, Sendable {
        case pending, approved, denied, expired, cancelled
    }

    let requestId: String
    let origin: String
    let host: String
    let cardLabel: String
    let amount: String
    let merchant: String
    let reason: String
    let state: State
    let fill: String?
    let fillError: String?
    let expiresAt: Double
    let decidedAt: Double?
    let now: Double

    func matches(_ command: PaymentCommand) -> Bool {
        origin == command.origin && cardLabel == command.cardLabel
    }
}

nonisolated enum PaymentLookup: Equatable, Sendable {
    case loading
    case failed
    case unverified(featureMissing: Bool)
    case verified(PaymentDetails, deadline: Date)

    init(_ details: PaymentDetails, for command: PaymentCommand?, receivedAt: Date = .now) {
        guard let command, details.matches(command) else {
            self = .unverified(featureMissing: false)
            return
        }
        self = .verified(details, deadline: receivedAt.addingTimeInterval(details.expiresAt - details.now))
    }
}

nonisolated struct PaymentCardState: Equatable, Sendable {
    var lookup: PaymentLookup = .loading
    var isApproved = false
    var failure: String?
}

nonisolated func endedPaymentNotice(_ details: PaymentDetails) -> String? {
    if details.state == .expired {
        let time = Date(timeIntervalSince1970: details.expiresAt).formatted(date: .omitted, time: .shortened)
        return String(localized: "This payment request expired at \(time).")
    }
    if details.state == .approved { return String(localized: "This payment request was approved on another device.") }
    if details.state == .denied { return String(localized: "This payment request was denied on another device.") }
    if details.state == .cancelled { return String(localized: "This payment request was cancelled.") }
    return nil
}

nonisolated struct PluginStatus: Decodable, Equatable, Sendable {
    let pluginVersion: String
    let installId: String
    let apnsConfigured: Bool
    let http2: Bool
    let devices: Int
    var features: [String]? = nil
    var gate: Bool? = nil

    var supportsPayments: Bool {
        features?.contains("payments") == true
    }
}

nonisolated struct VaultResult: Decodable, Sendable {
    struct CrewPayment: Decodable, Sendable {
        let state: PaymentDetails.State?
        let fill: String?
        let fillError: String?
        let missingShop: String?
        let origin: String?

        private enum CodingKeys: String, CodingKey {
            case state, fill, origin
            case fillError = "fill_error"
            case missingShop = "missing_shop"
        }
    }

    let success: Bool?
    let errorType: String?
    let error: String?
    let kind: String?
    let origin: String?
    let fields: [String]?
    let crewPayment: CrewPayment?

    private enum CodingKeys: String, CodingKey {
        case success, error, kind, origin, fields
        case errorType = "error_type"
        case crewPayment = "crew_payment"
    }

    init?(_ text: String) {
        guard let outer = try? JSONDecoder().decode(Self.self, from: Data(text.utf8)) else { return nil }
        guard outer.success == nil, outer.errorType == nil, let inner = outer.error, let decoded = try? JSONDecoder().decode(Self.self, from: Data(inner.utf8)) else {
            self = outer
            return
        }
        self = decoded
    }
}

nonisolated struct PaymentReceipt: Equatable, Sendable {
    enum Tone: Sendable {
        case approved, denied, warning, neutral
    }

    let text: String
    let tone: Tone

    init?(_ call: ToolCall) {
        let arguments = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
        guard call.name == "browser_vault", arguments["action"] as? String == "fill", let text = call.result, let result = VaultResult(text) else { return nil }
        let isPayment = result.kind == "payment" || result.crewPayment != nil || result.errorType == "payment_declined" || arguments["amount"] != nil
        guard isPayment, result.errorType?.hasPrefix("crew_") != true else { return nil }
        let amount = (arguments["amount"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let host = (result.origin ?? result.crewPayment?.origin).flatMap { URLComponents(string: $0)?.encodedHost }
        let total = [amount, host.map { String(localized: "at \($0)") }].compactMap(\.self).joined(separator: " ")
        let notFilled = { (reason: String) in
            PaymentReceipt(text: String(localized: "Approved, but the card wasn't filled: \(reason)"), tone: .warning)
        }
        let leftShop = String(localized: "the page left \(host ?? String(localized: "the shop"))")
        if let state = result.crewPayment?.state {
            if state == .denied {
                self.init(text: String(localized: "Denied \(total)").trimmingCharacters(in: .whitespaces), tone: .denied)
                return
            }
            if state == .expired {
                self.init(text: String(localized: "Payment request expired"), tone: .neutral)
                return
            }
            if state == .cancelled {
                self.init(text: String(localized: "Payment request cancelled"), tone: .neutral)
                return
            }
            if state == .approved, result.crewPayment?.fill == "filled" {
                self.init(text: String(localized: "Approved \(total)").trimmingCharacters(in: .whitespaces), tone: .approved)
                return
            }
            if state == .approved, let error = result.crewPayment?.fillError {
                self = notFilled(Self.reason(error, leftShop: leftShop))
                return
            }
        }
        if result.errorType == "payment_declined" {
            self.init(text: String(localized: "Payment not approved"), tone: .neutral)
            return
        }
        if let type = result.errorType {
            self = notFilled(Self.reason(type, leftShop: leftShop))
            return
        }
        if result.success == true, result.fields?.contains("cc-number") == true {
            self.init(text: String(localized: "Approved \(total)").trimmingCharacters(in: .whitespaces), tone: .approved)
            return
        }
        if result.success == true || result.error?.contains("No payment form fields") == true {
            self = notFilled(Self.reason("no_fields", leftShop: leftShop))
            return
        }
        self = notFilled(Self.reason("error", leftShop: leftShop))
    }

    private init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    private static func reason(_ code: String, leftShop: String) -> String {
        if ["origin_mismatch", "origin_changed"].contains(code) { return leftShop }
        if code == "no_fields" { return String(localized: "card fields not found") }
        if code == "human_has_control" { return String(localized: "you're controlling the browser") }
        return String(localized: "the browser didn't respond")
    }
}

extension Turn {
    nonisolated var paymentReceipts: [PaymentReceipt] {
        work.compactMap { item in
            guard case .tool(let call) = item.kind else { return nil }
            return PaymentReceipt(call)
        }
    }

    nonisolated var missingShop: String? {
        let results = work.compactMap { item -> String? in
            guard case .tool(let call) = item.kind, call.name == "browser_vault" else { return nil }
            return call.result
        }
        guard status != .streaming, let last = results.last, let origin = VaultResult(last)?.crewPayment?.missingShop else { return nil }
        return URLComponents(string: origin)?.encodedHost?.lowercased()
    }
}

nonisolated func shopHost(from input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let host = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")?.encodedHost?.lowercased(),
          host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
    else { return nil }
    return host
}

nonisolated struct MasterCard: Decodable, Equatable, Sendable {
    let label: String?
    let last4: String?
    let problem: String?
}

nonisolated struct Shop: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let origin: String
    let host: String
    let createdAt: Double
    let lastPaidAt: Double?
    let stale: Bool
    let punycode: Bool
}

nonisolated struct ShopList: Decodable, Equatable, Sendable {
    var card: MasterCard
    var shops: [Shop]
    let terminalBackend: String?
    let gate: Bool?
}

nonisolated struct ShopCreated: Decodable, Sendable {
    let shop: Shop
}

nonisolated struct PaymentsError: LocalizedError, Equatable {
    let code: String
    let reason: String?

    func message(host: String?) -> String {
        if code == "invalid_site" {
            if reason == "not_https" { return String(localized: "Use an https address.") }
            if reason == "ip_address" { return String(localized: "Use a name, not an IP address.") }
            if reason == "localhost" { return String(localized: "That isn't a public website.") }
            if reason == "port" { return String(localized: "Use the standard https port.") }
            return String(localized: "Enter a website.")
        }
        if code == "duplicate_shop" { return String(localized: "\(host ?? String(localized: "This site")) is already a shop.") }
        if code == "no_card" { return String(localized: "Add a card on the server first.") }
        if code == "several_cards" { return String(localized: "Keep one card without a website on the server.") }
        if ["invalid_profile", "unknown_profile"].contains(code) { return String(localized: "Couldn't load shops.") }
        return String(localized: "Couldn't reach Hermes. Try again.")
    }

    var errorDescription: String? {
        message(host: nil)
    }
}

nonisolated private struct PaymentsErrorBody: Decodable {
    struct Detail: Decodable {
        let code: String
        let reason: String?
    }

    let detail: Detail
}

nonisolated func paymentsCall<Response: Decodable>(_ path: String, query: [URLQueryItem] = [], method: String? = nil, body: [String: String]? = nil, on server: URL, with urlSession: URLSession, as type: Response.Type = Response.self) async throws -> Response {
    var request = hermesRequest("api/plugins/crew-push/\(path)", on: server, json: body)
    if let method { request.httpMethod = method }
    if !query.isEmpty { request.url?.append(queryItems: query) }
    let (data, response) = try await urlSession.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        if let error = try? JSONDecoder().decode(PaymentsErrorBody.self, from: data) { throw PaymentsError(code: error.detail.code, reason: error.detail.reason) }
        throw HermesError.server(status)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Response.self, from: data)
}

nonisolated func lookUpPayment(_ request: ApprovalRequest, on server: URL, with urlSession: URLSession) async -> PaymentLookup {
    let command = PaymentCommand(request.command)
    guard let requestID = request.requestID, command != nil else { return .unverified(featureMissing: false) }
    do {
        guard try await paymentsCall("status", on: server, with: urlSession, as: PluginStatus.self).supportsPayments else { return .unverified(featureMissing: true) }
    } catch HermesError.server(404, _) {
        return .unverified(featureMissing: true)
    } catch {
        return .failed
    }
    for attempt in 0..<2 {
        do {
            let details = try await paymentsCall("payments/requests/\(requestID)", on: server, with: urlSession, as: PaymentDetails.self)
            return PaymentLookup(details, for: command)
        } catch let error as PaymentsError where error.code == "unknown_request" {
            guard attempt == 0 else { return .unverified(featureMissing: false) }
        } catch {
            guard attempt == 0 else { return .failed }
        }
        try? await Task.sleep(for: .milliseconds(300))
    }
    return .failed
}
