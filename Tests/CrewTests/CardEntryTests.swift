import Foundation
import Synchronization
import Testing

nonisolated private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/payments")

private func decoded<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: Data(contentsOf: fixtures.appending(path: "\(name).json")))
}

private let october2026 = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 17))!

private func entry(number: String = "4242 4242 4242 4242", expiry: String = "12/30", cvc: String = "123", name: String = "", label: String = "Shopping card") -> CardEntry {
    CardEntry(number: number, expiry: expiry, cvc: cvc, name: name, label: label)
}

@Test(arguments: [
    ("4242 4242 4242 4242", nil),
    ("4242-4242-4242-4242", nil),
    ("378282246310005", nil),
    ("6011111111111117", nil),
    ("4242 4242 4242 4241", "Check the card number."),
    ("4242 4242 4242 424x", "Check the card number."),
    ("42424242", "Check the card number."),
    ("", "Check the card number."),
    ("４２４２４２４２４２４２４２４２", "Check the card number."),
])
func cardNumbers(number: String, expected: String?) {
    #expect(entry(number: number, cvc: number.hasPrefix("37") ? "1234" : "123").problem(.number) == expected)
}

@Test(arguments: [
    ("12/30", nil),
    ("12/2030", nil),
    ("10/26", nil),
    ("9/2026", "This card has expired."),
    ("09/26", "This card has expired."),
    ("01/25", "This card has expired."),
    ("13/30", "Check the expiry date."),
    ("00/30", "Check the expiry date."),
    ("12/3", "Check the expiry date."),
    ("12/2050", "Check the expiry date."),
    ("1230", "Check the expiry date."),
    ("", "Check the expiry date."),
])
func expiryDates(expiry: String, expected: String?) {
    #expect(entry(expiry: expiry).problem(.expiry, now: october2026, calendar: Calendar(identifier: .gregorian)) == expected)
}

@Test func securityCodeLengthFollowsTheBrand() {
    #expect(entry(cvc: "123").problem(.cvc) == nil)
    #expect(entry(cvc: "1234").problem(.cvc) == "Enter the 3 digit code.")
    #expect(entry(cvc: "12").problem(.cvc) == "Enter the 3 digit code.")
    #expect(entry(number: "3782 822463 10005", cvc: "1234").problem(.cvc) == nil)
    #expect(entry(number: "3782 822463 10005", cvc: "123").problem(.cvc) == "Enter the 4 digit code.")
    #expect(entry(number: "37", cvc: "123").problem(.cvc) == "Enter the 4 digit code.")
    #expect(entry(number: "", cvc: "12").problem(.cvc) == "Enter the 3 or 4 digit code.")
}

@Test(arguments: [
    ("Shopping card", nil),
    ("Résa 2026", nil),
    ("  Travel  ", nil),
    ("", "Use up to 40 letters, digits and spaces."),
    (String(repeating: "e\u{301}", count: 21), "Use up to 40 letters, digits and spaces."),
    (String(repeating: "x", count: 41), "Use up to 40 letters, digits and spaces."),
    ("Visa •••• 9999", "Use up to 40 letters, digits and spaces."),
    ("Bob's card", "Use up to 40 letters, digits and spaces."),
    ("Card · shop", "Use up to 40 letters, digits and spaces."),
    ("Two\nlines", "Use up to 40 letters, digits and spaces."),
    ("Zero\u{200B}width", "Use up to 40 letters, digits and spaces."),
])
func labels(label: String, expected: String?) {
    #expect(entry(label: label).problem(.label) == expected)
}

@Test func namesAreOptionalAndShort() {
    #expect(entry(name: "").problem(.name) == nil)
    #expect(entry(name: "Test Card").problem(.name) == nil)
    #expect(entry(name: String(repeating: "x", count: 65)).problem(.name) == "Use a shorter name.")
    #expect(entry(name: "Test\u{200B}Card").problem(.name) == nil)
    #expect(entry(name: String(repeating: "e\u{301}", count: 40)).problem(.name) == "Use a shorter name.")
}

@Test func theBodyCarriesNormalisedValues() {
    let card = entry(number: "4000 0566 5566 5556", expiry: "3/31", cvc: "321", name: " Test Card ", label: " Travel card ")
    #expect(card.body == ["card_number": "4000056655665556", "exp_month": "03", "exp_year": "2031", "cvc": "321", "cardholder_name": "Test Card", "label": "Travel card"])
    #expect(card.isValid(now: october2026))
    #expect(!entry(cvc: "").isValid(now: october2026))
}

@Test func formattingAsTyped() {
    #expect(CardEntry.formattedNumber("4242424242424242") == "4242 4242 4242 4242")
    #expect(CardEntry.formattedNumber("4242 42a") == "4242 42")
    #expect(CardEntry.formattedNumber("378282246310005") == "3782 822463 10005")
    #expect(CardEntry.formattedNumber(String(repeating: "4", count: 25)).filter(\.isNumber).count == 19)
    #expect(CardEntry.formattedExpiry("1230") == "12/30")
    #expect(CardEntry.formattedExpiry("12/2030") == "12/2030")
    #expect(CardEntry.formattedExpiry("1") == "1")
    #expect(CardEntry.formattedExpiry("825") == "08/25")
    #expect(CardEntry.formattedExpiry("08/25") == "08/25")
    #expect(CardEntry.formattedExpiry("0") == "0")
    #expect(CardEntry.formattedExpiry("12") == "12")
    #expect(entry(number: "4242 4242 4242 4242").isNumberComplete)
    #expect(!entry(number: "4242 4242 4242 424").isNumberComplete)
    #expect(entry(number: "3782 822463 10005").isNumberComplete)
}

@Test func cardRoutesDecode() throws {
    #expect(try decoded("card-set", as: CardSet.self).card == MasterCard(label: "Shopping card", last4: "4242", problem: nil, codeMismatch: false))
    let shops = try decoded("shops-updated", as: ShopsUpdated.self).shops
    #expect(shops.map(\.host) == ["www.apotea.se", "www.zalando.se"])
    #expect(shops.allSatisfy { !$0.stale })
    #expect(try decoded("status", as: PluginStatus.self).supportsCardEntry)
    #expect(try !decoded("real/real-status", as: PluginStatus.self).supportsCardEntry)
}

@Test(arguments: [
    ("error-invalid-card-number", "Check the card number."),
    ("error-invalid-card-expiry", "Check the expiry date."),
    ("error-invalid-card-expired", "This card has expired."),
    ("error-invalid-card-cvc", "Enter the 3 or 4 digit code."),
    ("error-invalid-card-name", "Use a shorter name."),
    ("error-invalid-card-label", "Use up to 40 letters, digits and spaces."),
    ("error-invalid-card-body", "Couldn't reach Hermes. Try again."),
    ("error-login-off", "Payments are off: this server has no dashboard login."),
    ("error-payment-pending", "Finish or deny the waiting payment first."),
    ("error-vault-error", "Couldn't save the card on the server."),
    ("error-several-cards", "Keep one card without a website on the server."),
])
func cardErrorsUseTheContractText(name: String, expected: String) async throws {
    do {
        _ = try await paymentsCall("error/\(name)", on: URL(string: "https://errors.test")!, with: StubProtocol.session, as: CardSet.self)
        Issue.record("no error")
    } catch let error as PaymentsError {
        #expect(error.message(host: nil) == expected)
    }
}

@Test func paymentsCallsNeverFollowARedirect() async throws {
    RedirectProtocol.followed.withLock { $0 = [] }
    await #expect(throws: HermesError.server(307)) {
        try await paymentsCall("payments/card", method: "PUT", body: ["card_number": "4242424242424242"], on: URL(string: "https://redirect.test")!, with: RedirectProtocol.session, as: CardSet.self)
    }
    #expect(RedirectProtocol.followed.withLock { $0 } == ["https://redirect.test/api/plugins/crew-push/payments/card"])
}

private func shopList(card: MasterCard = MasterCard(label: "Shopping card", last4: "4242", problem: nil), stale: [Bool] = [false], gate: Bool? = true) -> ShopList {
    ShopList(
        card: card,
        shops: stale.enumerated().map { Shop(id: "v\($0.offset)", origin: "https://s\($0.offset).example.com", host: "s\($0.offset).example.com", createdAt: 0, lastPaidAt: nil, stale: $0.element, punycode: false) },
        terminalBackend: "docker", gate: gate
    )
}

@Test func cardButtonsNeedOnlineTheGateAndANewCrewPush() {
    let ready = ShopsControls(list: shopList(stale: [true, false, true]), isOnline: true, supportsCardEntry: true)
    #expect(ready.hasCard && ready.showsCardButton && ready.canEditCard && ready.showsUpdateShops && ready.canUpdateShops && ready.canAddShop)
    #expect(ready.staleCount == 2)
    #expect(ready.staleText == "2 shops still use the old card. Update Shops copies the current card to them.")
    #expect(ShopsControls(list: shopList(stale: [true]), isOnline: true, supportsCardEntry: true).staleText == "1 shop still uses the old card. Update Shops copies the current card to it.")

    let offline = ShopsControls(list: shopList(stale: [true]), isOnline: false, supportsCardEntry: true)
    #expect(offline.showsCardButton && !offline.canEditCard && offline.showsUpdateShops && !offline.canUpdateShops && !offline.canAddShop)

    for gate in [false, nil] as [Bool?] {
        let gated = ShopsControls(list: shopList(stale: [true], gate: gate), isOnline: true, supportsCardEntry: true)
        #expect(!gated.canEditCard && !gated.canUpdateShops && gated.canAddShop)
    }

    let old = ShopsControls(list: shopList(card: MasterCard(label: nil, last4: nil, problem: "missing"), stale: []), isOnline: true, supportsCardEntry: false)
    #expect(!old.showsCardButton && !old.canEditCard && !old.showsUpdateShops && !old.canAddShop)
    #expect(old.noCardText == "Add one card on the server without a website. Update crew-push to add it from Crew.")

    let noCard = ShopsControls(list: shopList(card: MasterCard(label: nil, last4: nil, problem: "missing"), stale: []), isOnline: true, supportsCardEntry: true)
    #expect(noCard.showsCardButton && noCard.canEditCard && !noCard.canAddShop)
    #expect(noCard.noCardText == "Add the card Crew copies to each shop you add. Bots never see the number.")

    let several = ShopsControls(list: shopList(card: MasterCard(label: nil, last4: nil, problem: "several"), stale: [true]), isOnline: true, supportsCardEntry: true)
    #expect(!several.showsCardButton && !several.canEditCard && !several.showsUpdateShops)
    #expect(several.noCardText == "Keep one card without a website; Crew can't tell which to use.")

    let fresh = ShopsControls(list: shopList(stale: [false]), isOnline: true, supportsCardEntry: true)
    #expect(!fresh.showsUpdateShops)
}

@Test func aSavedCodeThatDoesNotFitTheCardIsFlagged() throws {
    let mismatch = try decoded("payments-code-mismatch", as: ShopList.self)
    #expect(mismatch.card == MasterCard(label: "Shopping card", last4: "4444", problem: nil, codeMismatch: true))
    #expect(ShopsControls(list: mismatch, isOnline: true, supportsCardEntry: true).showsCodeWarning)
    #expect(ShopsControls(list: mismatch, isOnline: false, supportsCardEntry: true).showsCodeWarning)
    #expect(try !ShopsControls(list: decoded("payments", as: ShopList.self), isOnline: true, supportsCardEntry: true).showsCodeWarning)
    let oldCrewPush = try JSONDecoder().decode(MasterCard.self, from: Data(#"{"label": "Shopping card", "last4": "4242", "problem": null}"#.utf8))
    #expect(oldCrewPush.codeMismatch == nil)
    #expect(!ShopsControls(list: shopList(card: oldCrewPush), isOnline: true, supportsCardEntry: true).showsCodeWarning)
    for problem in ["missing", "several"] {
        let card = MasterCard(label: nil, last4: nil, problem: problem, codeMismatch: true)
        #expect(!ShopsControls(list: shopList(card: card), isOnline: true, supportsCardEntry: true).showsCodeWarning)
    }
}

nonisolated final class RedirectProtocol: URLProtocol {
    static let followed = Mutex<[String]>([])
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectProtocol.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        RedirectProtocol.followed.withLock { $0.append(url.absoluteString) }
        let target = URL(string: "http://elsewhere.test/steal")!
        let response = HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}
