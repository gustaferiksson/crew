import AppKit
import SwiftUI
import Testing

private let payments = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/payments")

private func recorded(_ name: String, host: String) throws -> Data {
    let text = try String(contentsOf: payments.appending(path: "\(name).json"), encoding: .utf8)
    return Data(text.replacingOccurrences(of: "www.zalando.se", with: host).utf8)
}

private func approval(host: String) throws -> ApprovalRequest {
    let frame = try JSONDecoder().decode(ServerRequest.self, from: try recorded("approval-frame", host: host))
    guard case .approval(let approval) = PendingRequest(frame) else { throw CocoaError(.coderReadCorrupt) }
    return approval
}

private func verified(_ approval: ApprovalRequest, host: String) throws -> PaymentLookup {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let details = try decoder.decode(PaymentDetails.self, from: try recorded("request-pending", host: host))
    return PaymentLookup(details, for: PaymentCommand(approval.command))
}

private func card(_ approval: ApprovalRequest, _ lookup: PaymentLookup) -> some View {
    PaymentCard(request: approval, state: PaymentCardState(lookup: lookup), botName: "Scout", avatar: EmptyView(), respond: { _ in }, retry: {}, expire: {})
        .frame(maxWidth: 560)
}

@MainActor private func height(_ view: some View, proposing size: CGSize) -> CGFloat {
    NSHostingController(rootView: view).sizeThatFits(in: size).height
}

@Test(arguments: ["www.zalando.se", "xn--zaando-5ve.se"])
@MainActor func thePaymentCardsMinimumHeightNeverSetsTheWindows(host: String) throws {
    let approval = try approval(host: host)
    let lookups = [try verified(approval, host: host), .loading, .failed, .unverified(featureMissing: true)]
    let approvalCardMinimum = height(ApprovalCard(request: approval, botName: "Scout") { _ in }.frame(maxWidth: 560), proposing: .zero)
    for lookup in lookups {
        let minimum = height(card(approval, lookup), proposing: .zero)
        let ideal = height(card(approval, lookup), proposing: CGSize(width: 560, height: CGFloat.infinity))
        #expect(minimum <= approvalCardMinimum, "\(lookup)")
        #expect(minimum < 160, "\(lookup) \(minimum)")
        #expect(ideal > minimum + 60, "\(lookup) \(minimum) \(ideal)")
    }
}

@Test @MainActor func thePaymentCardShowsItsFullBodyWhenThereIsRoom() throws {
    let approval = try approval(host: "www.zalando.se")
    let lookup = try verified(approval, host: "www.zalando.se")
    let ideal = height(card(approval, lookup), proposing: CGSize(width: 560, height: CGFloat.infinity))
    let roomy = height(card(approval, lookup), proposing: CGSize(width: 560, height: 2000))
    let short = height(card(approval, lookup), proposing: CGSize(width: 560, height: 200))
    #expect(roomy == ideal)
    #expect(short <= 200)
}
