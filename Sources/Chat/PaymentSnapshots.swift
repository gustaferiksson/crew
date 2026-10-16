import SwiftUI

extension ChatFixture {
    static let payments: [ChatFixture] = [.payment, .paymentHolding, .paymentApproved, .paymentLoading, .paymentFailed, .paymentUnverified, .paymentPunycode, .paymentCountdown, .paymentNotice, .paymentOffer, .paymentReceipts]

    var isPayment: Bool {
        Self.payments.contains(self)
    }

    var paymentRequest: PendingRequest? {
        guard isPayment, ![.paymentNotice, .paymentOffer, .paymentReceipts].contains(self) else { return nil }
        let host = self == .paymentPunycode ? "xn--zaando-5ve.se" : "www.zalando.se"
        return .approval(ApprovalRequest(
            id: "srq-7c1e0b2a9d4f",
            command: "Fill payment card 'Shopping card •••• 4242 · \(host)' on https://\(host)",
            description: "Fill the payment card on \(host)",
            toolName: "browser_vault",
            choices: [.once, .session, .always, .deny],
            requestID: "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54"
        ))
    }

    var paymentState: PaymentCardState? {
        guard paymentRequest != nil else { return nil }
        let host = self == .paymentPunycode ? "xn--zaando-5ve.se" : "www.zalando.se"
        let details = PaymentDetails(
            requestId: "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54", origin: "https://\(host)", host: host, cardLabel: "Shopping card •••• 4242",
            amount: "499 kr", merchant: "Zalando", reason: "Winter boots, size 43", state: .pending, fill: nil, fillError: nil,
            expiresAt: 300, decidedAt: nil, now: 0
        )
        let verified = PaymentLookup.verified(details, deadline: .now.addingTimeInterval(self == .paymentCountdown ? 45 : 240))
        if self == .paymentLoading { return PaymentCardState(lookup: .loading) }
        if self == .paymentFailed { return PaymentCardState(lookup: .failed) }
        if self == .paymentUnverified { return PaymentCardState(lookup: .unverified(featureMissing: true)) }
        return PaymentCardState(lookup: verified, isApproved: self == .paymentApproved)
    }

    var paymentNotice: String? {
        guard self == .paymentNotice else { return nil }
        let expiry = Calendar.current.date(bySettingHour: 14, minute: 7, second: 0, of: .now) ?? .now
        return String(localized: "This payment request expired at \(expiry.formatted(date: .omitted, time: .shortened)).")
    }

    var shopOffer: String? {
        self == .paymentOffer ? "www.zalando.de" : nil
    }

    static func shoppingTurns(_ now: Date, fill: String?) -> [Turn] {
        let start = now.addingTimeInterval(-90)
        let browse = [
            WorkItem(id: "p1-w0", kind: .tool(ToolCall(name: "browser_navigate", subject: "https://www.zalando.se/winter-boots", arguments: #"{"url": "https://www.zalando.se/winter-boots"}"#, result: #"{"success": true}"#, status: .success)), startedAt: start.addingTimeInterval(2), duration: 3),
            WorkItem(id: "p1-w1", kind: .tool(ToolCall(name: "browser_click", subject: "Add to bag", arguments: #"{"ref": "Add to bag"}"#, result: #"{"success": true}"#, status: .success)), startedAt: start.addingTimeInterval(6), duration: 1),
            WorkItem(id: "p1-w2", kind: .tool(ToolCall(name: "browser_vault", subject: "", arguments: #"{"action": "list"}"#, result: #"{"success": true, "items": []}"#, status: .success)), startedAt: start.addingTimeInterval(8), duration: 1),
        ]
        let fillCall = WorkItem(
            id: "p1-w3",
            kind: .tool(ToolCall(name: "browser_vault", subject: "", arguments: #"{"action": "fill", "handle": "vault_3f9a1c2b7d4e", "amount": "499 kr", "merchant": "Zalando", "reason": "Winter boots, size 43"}"#, result: fill, status: fill.map(toolStatus(result:)) ?? .running)),
            startedAt: start.addingTimeInterval(10),
            duration: fill == nil ? nil : 12
        )
        return [
            Turn(
                id: "p0", prompt: Prompt(text: "Can you order the black winter boots in size 43 from Zalando?", sentAt: start.addingTimeInterval(-600)),
                reply: "Found them: Sorel Caribou, black, size 43 for 499 kr. Should I go ahead?", status: .complete,
                startedAt: start.addingTimeInterval(-600), finishedAt: start.addingTimeInterval(-560)
            ),
            Turn(
                id: "p1", prompt: Prompt(text: "Yes, buy them.", sentAt: start), work: browse + [fillCall],
                reply: fill == nil ? "" : "Done, order 4471 is confirmed. The shop will email the receipt.",
                status: fill == nil ? .streaming : .complete, startedAt: start, finishedAt: fill == nil ? nil : start.addingTimeInterval(40)
            ),
        ]
    }

    static func receiptTurns(_ now: Date) -> [Turn] {
        let outcomes: [(String, String)] = [
            ("r1", #"{"success": false, "error_type": "payment_declined", "crew_payment": {"request_id": "a", "state": "denied", "fill": null, "fill_error": null}}"#),
            ("r2", #"{"success": false, "error_type": "payment_declined", "crew_payment": {"request_id": "b", "state": "expired", "fill": null, "fill_error": null}}"#),
            ("r3", #"{"success": false, "kind": "payment", "origin": "https://www.zalando.se", "crew_payment": {"request_id": "c", "state": "approved", "fill": "not_filled", "fill_error": "no_fields"}}"#),
            ("r4", #"{"success": true, "kind": "payment", "origin": "https://www.zalando.se", "fields": ["cc-number", "cc-csc"], "crew_payment": {"request_id": "d", "state": "approved", "fill": "filled", "fill_error": null}}"#),
        ]
        let turns = outcomes.enumerated().map { index, outcome in
            let start = now.addingTimeInterval(Double(index - outcomes.count) * 300)
            return Turn(
                id: outcome.0, prompt: Prompt(text: ["Buy the boots.", "Try again?", "Pay for the boots now.", "One more time."][index], sentAt: start),
                work: [WorkItem(id: "\(outcome.0)-w0", kind: .tool(ToolCall(name: "browser_vault", subject: "", arguments: #"{"action": "fill", "amount": "499 kr"}"#, result: outcome.1, status: toolStatus(result: outcome.1))), startedAt: start.addingTimeInterval(2), duration: 8)],
                reply: ["You denied it, so I stopped.", "Nobody answered, so the request expired.", "The card fields are in a payment frame I can't fill.", "Paid. Order 4471 is confirmed."][index],
                status: .complete, startedAt: start, finishedAt: start.addingTimeInterval(20)
            )
        }
        let added = Turn(
            id: "r0", notice: String(localized: "Added www.zalando.de to Shops"), hiddenText: "I added https://www.zalando.de to your shops. Continue the purchase.",
            status: .complete, startedAt: now.addingTimeInterval(-1600), finishedAt: now.addingTimeInterval(-1590)
        )
        return [added] + turns
    }
}

struct ShopsFixtureScreen: View {
    let snapshot: Snapshot

    private let scout = Bot(
        name: "scout", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil,
        meta: BotMeta(title: "Scout", color: "#38bdf8"), metaRevision: nil
    )

    private var list: ShopList {
        let day = 24.0 * 3600
        let shops = [
            Shop(id: "v1", origin: "https://www.zalando.se", host: "www.zalando.se", createdAt: Date.now.timeIntervalSince1970 - 9 * day, lastPaidAt: Date.now.timeIntervalSince1970 - 2 * day, stale: false, punycode: false),
            Shop(id: "v2", origin: "https://www.apotea.se", host: "www.apotea.se", createdAt: Date.now.timeIntervalSince1970 - 4 * day, lastPaidAt: nil, stale: snapshot == .inspectorShops, punycode: false),
            Shop(id: "v3", origin: "https://xn--zaando-5ve.se", host: "xn--zaando-5ve.se", createdAt: Date.now.timeIntervalSince1970 - day, lastPaidAt: nil, stale: false, punycode: true),
        ]
        if snapshot == .inspectorShopsEmpty { return ShopList(card: MasterCard(label: "Shopping card", last4: "4242", problem: nil), shops: [], terminalBackend: "docker", gate: true) }
        if snapshot == .inspectorShopsNoCard { return ShopList(card: MasterCard(label: nil, last4: nil, problem: "missing"), shops: [], terminalBackend: "local", gate: false) }
        if snapshot == .inspectorShopsSeveral { return ShopList(card: MasterCard(label: nil, last4: nil, problem: "several"), shops: Array(shops.prefix(1)), terminalBackend: "local", gate: true) }
        return ShopList(card: MasterCard(label: "Shopping card", last4: "4242", problem: nil), shops: shops, terminalBackend: "local", gate: true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ShopsCard(bot: scout, isBrowserOff: snapshot == .inspectorShopsEmpty, fixture: list)
                    .padding(16)
            }
            .navigationTitle("Scout")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .sheet(isPresented: .constant([.addShop, .addShopError].contains(snapshot))) {
            AddShopSheet(
                profile: "scout",
                site: snapshot == .addShop ? "https://zаlando.se/checkout?step=2" : "www.zalando.se",
                failure: snapshot == .addShopError ? String(localized: "www.zalando.se is already a shop.") : nil
            ) { _ in }
        }
    }
}
