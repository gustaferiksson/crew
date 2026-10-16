import Foundation
import Testing

nonisolated private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/payments")

nonisolated private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixtures.appending(path: "\(name).json"))
}

private func text(_ name: String) throws -> String {
    String(decoding: try fixture(name), as: UTF8.self)
}

private func decoded<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: try fixture(name))
}

private let fillArguments = #"{"action": "fill", "handle": "vault_3f9a1c2b7d4e", "amount": "499 kr", "merchant": "Zalando", "reason": "Winter boots, size 43"}"#

private func vaultCall(_ result: String?, arguments: String = fillArguments) -> ToolCall {
    ToolCall(name: "browser_vault", subject: "", arguments: arguments, result: result, status: result.map(toolStatus(result:)) ?? .running)
}

private func approvalFrame() throws -> ServerRequest {
    try JSONDecoder().decode(ServerRequest.self, from: try fixture("approval-frame"))
}

private let scout = Bot(
    name: "scout", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil,
    meta: BotMeta(title: "Scout"), metaRevision: nil
)

@Test func parsesThePaymentCommand() throws {
    let command = try #require(PaymentCommand("Fill payment card 'Shopping card •••• 4242 · www.zalando.se' on https://www.zalando.se"))
    #expect(command.cardLabel == "Shopping card •••• 4242")
    #expect(command.origin == "https://www.zalando.se")
    #expect(command.host == "www.zalando.se")
    #expect(command.last4 == "4242")
}

@Test func parsesLabelsWithQuotesAndMiddleDots() throws {
    let command = try #require(PaymentCommand("Fill payment card 'Gustaf's card · travel •••• 1881 · shop.example.com' on https://shop.example.com"))
    #expect(command.cardLabel == "Gustaf's card · travel •••• 1881")
    #expect(command.host == "shop.example.com")
    #expect(command.last4 == "1881")
}

@Test func parsesALabelWithoutLastFourOrHostSuffix() throws {
    let command = try #require(PaymentCommand("Fill payment card 'Test card' on https://gustaferiksson.github.io"))
    #expect(command.cardLabel == "Test card")
    #expect(command.last4 == nil)
    #expect(!isPunycode(command.host))
}

@Test func flagsPunycodeHosts() throws {
    let command = try #require(PaymentCommand("Fill payment card 'Shopping card •••• 4242 · xn--zaando-5ve.se' on https://xn--zaando-5ve.se"))
    #expect(isPunycode(command.host))
    #expect(command.cardLabel == "Shopping card •••• 4242")
}

@Test func rejectsOtherCommands() {
    #expect(PaymentCommand("rm -rf /tmp/cache") == nil)
    #expect(PaymentCommand("Fill payment card '' on https://www.zalando.se") == nil)
    #expect(PaymentCommand("Fill payment card 'Shopping card' on nowhere") == nil)
}

@Test func recordedApprovalFrameIsAPaymentWithItsRequestID() throws {
    guard case .approval(let approval) = PendingRequest(try approvalFrame()) else { Issue.record("not an approval"); return }
    #expect(approval.isPayment)
    #expect(approval.requestID == "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54")
    #expect(WaitingKind(try approvalFrame()) == .payment)
}

@Test func otherApprovalsAreNotPayments() throws {
    let request = try JSONDecoder().decode(ServerRequest.self, from: Data(#"{"id": "srq-1", "method": "approval", "params": {"session_id": "rt", "command": "npm publish", "choices": ["once", "deny"]}}"#.utf8))
    #expect(PendingRequest(request)?.isPayment == false)
    #expect(WaitingKind(request) == .approval)
}

@Test func matchingDetailsAreVerified() throws {
    let command = try #require(PaymentCommand("Fill payment card 'Shopping card •••• 4242 · www.zalando.se' on https://www.zalando.se"))
    let details = try decoded("request-pending", as: PaymentDetails.self)
    let received = Date(timeIntervalSince1970: 1_000)
    guard case .verified(let shown, let deadline) = PaymentLookup(details, for: command, receivedAt: received) else { Issue.record("not verified"); return }
    #expect(shown.amount == "499 kr")
    #expect(shown.merchant == "Zalando")
    #expect(deadline == received.addingTimeInterval(1760610240.0 - 1760609941.2))
}

@Test func mismatchedDetailsAreNotVerified() throws {
    let details = try decoded("request-pending", as: PaymentDetails.self)
    let otherHost = PaymentCommand("Fill payment card 'Shopping card •••• 4242 · www.zalando.de' on https://www.zalando.de")
    let otherCard = PaymentCommand("Fill payment card 'Shopping card •••• 1881 · www.zalando.se' on https://www.zalando.se")
    #expect(PaymentLookup(details, for: otherHost) == .unverified(featureMissing: false))
    #expect(PaymentLookup(details, for: otherCard) == .unverified(featureMissing: false))
    #expect(PaymentLookup(details, for: nil) == .unverified(featureMissing: false))
}

@Test func lookUpGivesTheRightCard() async throws {
    let verified = await lookUpPayment(try paymentApproval(), on: URL(string: "https://status.test")!, with: StubProtocol.session)
    guard case .verified(let details, _) = verified else { Issue.record("not verified: \(verified)"); return }
    #expect(details.requestId == "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54")
    #expect(await lookUpPayment(try paymentApproval(), on: URL(string: "https://down.test")!, with: StubProtocol.session) == .failed)
    #expect(await lookUpPayment(try paymentApproval(), on: URL(string: "https://missing.test")!, with: StubProtocol.session) == .unverified(featureMissing: true))
    #expect(await lookUpPayment(try paymentApproval(), on: URL(string: "https://absent.test")!, with: StubProtocol.session) == .unverified(featureMissing: true))
    #expect(await lookUpPayment(try paymentApproval(), on: URL(string: "https://unknown.test")!, with: StubProtocol.session) == .unverified(featureMissing: false))
}

private func paymentApproval() throws -> ApprovalRequest {
    guard case .approval(let approval) = PendingRequest(try approvalFrame()) else { throw CancellationError() }
    return approval
}

@Test func paymentShowsBeforeAnotherApproval() throws {
    let other = try JSONDecoder().decode(ServerRequest.self, from: Data(#"{"id": "srq-0", "method": "approval", "params": {"session_id": "rt-4b8e2f", "command": "npm publish", "choices": ["once", "deny"]}}"#.utf8))
    let session = ChatSession(fixture: scout, transcript: Transcript(), todos: [], requests: [other, try approvalFrame()])
    #expect(session.request?.id == "srq-7c1e0b2a9d4f")
    #expect(session.request?.isPayment == true)
}

@Test func cardLeavesWhenTheFillCompletesWithoutRequestCancel() throws {
    var transcript = Transcript()
    transcript.begin(prompt: "Buy the boots")
    transcript.apply(.toolStart(id: "call-1", name: "browser_vault", context: nil, arguments: fillArguments))
    let other = try JSONDecoder().decode(ServerRequest.self, from: Data(#"{"id": "srq-0", "method": "approval", "params": {"session_id": "rt-4b8e2f", "command": "npm publish", "choices": ["once", "deny"]}}"#.utf8))
    let session = ChatSession(fixture: scout, transcript: transcript, todos: [], requests: [try approvalFrame(), other], payments: ["srq-7c1e0b2a9d4f": PaymentCardState()])
    let event = try JSONDecoder().decode(GatewayEvent.self, from: Data(#"{"type": "tool.complete", "payload": {"tool_id": "call-1", "result": "{\"success\": true}"}}"#.utf8))
    session.apply(event)
    #expect(session.openRequests.map(\.id) == ["srq-0"])
    #expect(session.payments.isEmpty)
    #expect(session.request?.isPayment == false)
}

@Test func cardLeavesWhenTheTurnEnds() throws {
    var transcript = Transcript()
    transcript.begin(prompt: "Buy the boots")
    let session = ChatSession(fixture: scout, transcript: transcript, todos: [], requests: [try approvalFrame()])
    session.apply(try JSONDecoder().decode(GatewayEvent.self, from: Data(#"{"type": "message.complete", "payload": {"text": "Stopped."}}"#.utf8)))
    #expect(session.request == nil)
}

@Test(arguments: [
    ("fill-approved", "Approved 499 kr at www.zalando.se", PaymentReceipt.Tone.approved),
    ("fill-denied", "Denied 499 kr", .denied),
    ("fill-expired", "Payment request expired", .neutral),
    ("fill-cancelled", "Payment request cancelled", .neutral),
    ("fill-origin-changed", "Approved, but the card wasn't filled: the page left www.zalando.se", .warning),
    ("fill-no-fields", "Approved, but the card wasn't filled: card fields not found", .warning),
    ("fill-human-control", "Approved, but the card wasn't filled: you're controlling the browser", .warning),
    ("fill-error", "Approved, but the card wasn't filled: the browser didn't respond", .warning),
    ("fill-approved.raw", "Approved 499 kr at www.zalando.se", .approved),
    ("fill-declined.raw", "Payment not approved", .neutral),
    ("fill-origin-changed.raw", "Approved, but the card wasn't filled: the page left www.zalando.se", .warning),
    ("fill-origin-mismatch.raw", "Approved, but the card wasn't filled: the page left www.zalando.se", .warning),
    ("fill-no-fields.raw", "Approved, but the card wasn't filled: card fields not found", .warning),
    ("fill-partial.raw", "Approved, but the card wasn't filled: card fields not found", .warning),
    ("fill-human-control.raw", "Approved, but the card wasn't filled: you're controlling the browser", .warning),
    ("fill-error.raw", "Approved, but the card wasn't filled: the browser didn't respond", .warning),
])
func receiptRowFromTheFillResult(name: String, expected: String, tone: PaymentReceipt.Tone) throws {
    let receipt = try #require(PaymentReceipt(vaultCall(try text(name))))
    #expect(receipt.text == expected)
    #expect(receipt.tone == tone)
}

@Test(arguments: ["block-no-shop-card", "block-missing-details", "block-gate-off", "block-not-bot-chat", "block-one-at-a-time", "block-after-decline", "list-missing-shop"])
func blocksAndListsGiveNoReceipt(name: String) throws {
    let arguments = name.hasPrefix("list") ? #"{"action": "list"}"# : fillArguments
    #expect(PaymentReceipt(vaultCall(try text(name), arguments: arguments)) == nil)
    #expect(toolStatus(result: try text(name)) == (name.hasPrefix("block") ? .error : .success))
}

@Test func runningFillsAndOtherToolsGiveNoReceipt() throws {
    #expect(PaymentReceipt(vaultCall(nil)) == nil)
    #expect(PaymentReceipt(vaultCall(try text("fill-approved"), arguments: #"{"action": "list"}"#)) == nil)
    #expect(PaymentReceipt(ToolCall(name: "terminal", subject: "", arguments: fillArguments, result: try text("fill-approved"), status: .success)) == nil)
}

@Test func receiptsSurviveAHistoryReload() throws {
    let rows = #"""
    [
     {"id": 1, "role": "user", "content": "Buy the boots", "timestamp": 1760609900},
     {"id": 2, "role": "assistant", "content": "", "timestamp": 1760609930, "tool_calls": [{"id": "call-1", "function": {"name": "browser_vault", "arguments": "{\"action\": \"fill\", \"handle\": \"vault_3f9a1c2b7d4e\", \"amount\": \"499 kr\", \"merchant\": \"Zalando\", \"reason\": \"Winter boots\"}"}}]},
     {"id": 3, "role": "tool", "content": \#(String(data: try JSONEncoder().encode(try text("fill-approved")), encoding: .utf8)!), "timestamp": 1760609990, "tool_call_id": "call-1"},
     {"id": 4, "role": "assistant", "content": "Paid. Order 4471.", "timestamp": 1760610000}
    ]
    """#
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let transcript = Transcript(history: try decoder.decode([HistoryRow].self, from: Data(rows.utf8)))
    #expect(transcript.visible.turns.last?.paymentReceipts.map(\.text) == ["Approved 499 kr at www.zalando.se"])
}

@Test(arguments: ["list-missing-shop", "block-no-shop-card"])
func offerComesFromTheLastVaultResult(name: String) throws {
    var turn = Turn(id: "t", status: .complete, startedAt: .now)
    turn.work = [WorkItem(id: "w", kind: .tool(vaultCall(try text(name), arguments: #"{"action": "list"}"#)), startedAt: .now)]
    #expect(turn.missingShop == "www.zalando.de")
    turn.status = .streaming
    #expect(turn.missingShop == nil)
}

@Test func laterVaultResultsClearTheOffer() throws {
    var turn = Turn(id: "t", status: .complete, startedAt: .now)
    turn.work = [
        WorkItem(id: "w1", kind: .tool(vaultCall(try text("list-missing-shop"), arguments: #"{"action": "list"}"#)), startedAt: .now),
        WorkItem(id: "w2", kind: .tool(vaultCall(try text("fill-approved"))), startedAt: .now),
    ]
    #expect(turn.missingShop == nil)
}

@Test func hiddenContinuePromptReadsAsANotice() {
    var transcript = Transcript()
    transcript.begin(remote: "I added https://www.zalando.de to your shops. Continue the purchase.", displayKind: "hidden", at: .now)
    #expect(transcript.turns.last?.notice == "Added www.zalando.de to Shops")
    #expect(transcript.turns.last?.prompt == nil)
}

@Test func shopsDecodeEveryCardState() throws {
    let one = try decoded("payments", as: ShopList.self)
    #expect(one.card == MasterCard(label: "Shopping card", last4: "4242", problem: nil))
    #expect(one.shops.map(\.host) == ["www.zalando.se"])
    #expect(one.terminalBackend == "local")
    #expect(one.gate == true)
    #expect(try decoded("payments-no-card", as: ShopList.self).card.problem == "missing")
    #expect(try decoded("payments-several", as: ShopList.self).card.problem == "several")
    #expect(try decoded("shop-created", as: ShopCreated.self).shop.lastPaidAt == nil)
}

@Test(arguments: [
    ("error-invalid-site-not-https", "Use an https address."),
    ("error-invalid-site-ip-address", "Use a name, not an IP address."),
    ("error-invalid-site-localhost", "That isn't a public website."),
    ("error-invalid-site-no-host", "Enter a website."),
    ("error-invalid-site-port", "Use the standard https port."),
    ("error-duplicate-shop", "www.zalando.se is already a shop."),
    ("error-no-card", "Add a card on the server first."),
    ("error-several-cards", "Keep one card without a website on the server."),
    ("error-invalid-profile", "Couldn't load shops."),
    ("error-unknown-profile", "Couldn't load shops."),
])
func shopErrorsUseTheContractText(name: String, expected: String) async throws {
    do {
        _ = try await paymentsCall("error/\(name)", on: URL(string: "https://errors.test")!, with: StubProtocol.session, as: ShopList.self)
        Issue.record("no error")
    } catch let error as PaymentsError {
        #expect(error.message(host: "www.zalando.se") == expected)
    }
}

@Test func unknownShopAndRequestKeepTheirCodes() async throws {
    for (name, code) in [("error-unknown-shop", "unknown_shop"), ("error-unknown-request", "unknown_request")] {
        await #expect(throws: PaymentsError(code: code, reason: nil)) {
            try await paymentsCall("error/\(name)", on: URL(string: "https://errors.test")!, with: StubProtocol.session, as: ShopList.self)
        }
    }
}

@Test func endedRequestsExplainThemselves() throws {
    let expired = try decoded("request-expired", as: PaymentDetails.self)
    let time = Date(timeIntervalSince1970: 1760610240.0).formatted(date: .omitted, time: .shortened)
    #expect(endedPaymentNotice(expired) == "This payment request expired at \(time).")
    #expect(endedPaymentNotice(try decoded("request-approved", as: PaymentDetails.self)) == "This payment request was approved on another device.")
    #expect(endedPaymentNotice(try decoded("request-pending", as: PaymentDetails.self)) == nil)
}

@Test(arguments: [
    ("https://www.zalando.se/checkout?step=2", "www.zalando.se"),
    ("www.Zalando.se", "www.zalando.se"),
    ("bücher.de", "xn--bcher-kva.de"),
    ("  zalando.se  ", "zalando.se"),
])
func shopSiteParses(input: String, host: String) {
    #expect(shopHost(from: input) == host)
}

@Test func shopSiteNeedsADottedName() {
    #expect(shopHost(from: "") == nil)
    #expect(shopHost(from: "localhost") == nil)
    #expect(shopHost(from: "https://") == nil)
}

@Test func pushRoutesCarryTheRequest() throws {
    for name in ["push-payment", "push-payment-previews-off"] {
        let payload = try #require(JSONSerialization.jsonObject(with: try fixture(name)) as? [AnyHashable: Any])
        let route = try #require(PushRoute(userInfo: payload))
        #expect(route.kind == "payment")
        #expect(route.profile == "scout")
        #expect(route.requestID == "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54")
        #expect(route.expiresAt == Date(timeIntervalSince1970: 1760610240.0))
        #expect(!route.isStalePayment(at: Date(timeIntervalSince1970: 1760610239)))
        #expect(route.isStalePayment(at: Date(timeIntervalSince1970: 1760610240)))
    }
    let resolvedPayload = try #require(JSONSerialization.jsonObject(with: try fixture("push-payment-resolved")) as? [AnyHashable: Any])
    let resolved = try #require(PushRoute(userInfo: resolvedPayload))
    #expect(resolved.kind == "payment_resolved")
    #expect(resolved.requestID == "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54")
    #expect(!resolved.isStalePayment(at: .distantFuture))
}

@Test func pluginStatusAnnouncesPayments() throws {
    #expect(try decoded("status", as: PluginStatus.self).supportsPayments)
    #expect(try decoded("status", as: PluginStatus.self).gate == true)
    let old = try JSONDecoder.snake.decode(PluginStatus.self, from: Data(#"{"plugin_version": "0.3.2", "install_id": "x", "apns_configured": true, "http2": true, "devices": 1}"#.utf8))
    #expect(!old.supportsPayments)
}

private extension JSONDecoder {
    static var snake: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

nonisolated final class StubProtocol: URLProtocol {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let server = url.host() ?? ""
        let path = url.path()
        let (status, name): (Int, String) = if server == "errors.test" {
            (path.contains("unknown") ? 404 : path.contains("duplicate") || path.contains("card") ? 409 : 400, String(path.split(separator: "/").last ?? ""))
        } else if path.hasSuffix("/status") {
            server == "absent.test" ? (404, "") : server == "down.test" ? (500, "") : (200, server == "missing.test" ? "status-old" : "status")
        } else {
            server == "unknown.test" ? (404, "error-unknown-request") : (200, "request-pending")
        }
        let body = name == "status-old" ? Data(#"{"plugin_version": "0.3.2", "install_id": "x", "apns_configured": true, "http2": true, "devices": 1}"#.utf8) : (try? fixture(name)) ?? Data()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
