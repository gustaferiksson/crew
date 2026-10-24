import SwiftUI

struct PaymentCard<Avatar: View>: View {
    let request: ApprovalRequest
    let state: PaymentCardState
    let botName: String
    let avatar: Avatar
    var holdProgress = 0.0
    let respond: (ApprovalChoice) -> Void
    let retry: () -> Void
    let expire: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private var secondsLeft: Int?

    private var command: PaymentCommand? {
        PaymentCommand(request.command)
    }

    private var host: String {
        command?.host ?? String(localized: "an unknown site")
    }

    private var details: PaymentDetails? {
        guard case .verified(let details, _) = state.lookup else { return nil }
        return details
    }

    private var deadline: Date? {
        guard case .verified(_, let deadline) = state.lookup else { return nil }
        return deadline
    }

    private var isUnverified: Bool {
        if case .unverified = state.lookup { return true }
        return command == nil
    }

    private var isCompactHeight: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isCompactHeight {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                                .layoutPriority(2)
                            merchantLine
                                .layoutPriority(2)
                            status
                        }
                        if !isUnverified {
                            detailRows
                        }
                    }
                    .layoutPriority(1)
                    buttons
                        .layoutPriority(2)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    header
                        .layoutPriority(2)
                    merchantLine
                        .layoutPriority(2)
                    if !isUnverified {
                        detailRows
                            .layoutPriority(1)
                    }
                    status
                    buttons
                        .layoutPriority(2)
                }
            }
        }
        .padding(16)
        .background { Color.clear.glassEffect(in: .rect(cornerRadius: 28)) }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
        .task(id: deadline) { await countDown() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            avatar
            Text("\(request.requester ?? botName) wants to pay")
                .font(.subheadline.weight(.semibold))
                // iOS only: on the Mac a vertical pin raises the window's minimum height (#60).
                #if os(iOS)
                .fixedSize(horizontal: false, vertical: true)
                #endif
            Spacer(minLength: 8)
            if let secondsLeft {
                Text(Duration.seconds(secondsLeft), format: .time(pattern: .minuteSecond))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(secondsLeft < 15 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("\(secondsLeft) seconds left")
            }
        }
    }

    private var merchantLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Pay")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(host.map(String.init).joined(separator: "\u{200B}"))
                    .font(.title2.weight(.semibold))
                    .accessibilityLabel(host)
                    #if os(iOS)
                    .fixedSize(horizontal: false, vertical: true)
                    #endif
            }
            .accessibilityElement(children: .combine)
            if isPunycode(host) {
                Label("This address uses special characters and could imitate another site.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    #if os(iOS)
                    .fixedSize(horizontal: false, vertical: true)
                    #endif
            }
        }
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .vertical) {
                cardAndPurpose
                ScrollView {
                    cardAndPurpose
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicatorsFlash(onAppear: true)
            }
            Divider()
            detailRow("TOTAL") {
                Text(details?.amount ?? "000 kr")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
            }
            .layoutPriority(1)
        }
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
        .redacted(reason: details == nil ? .placeholder : [])
    }

    private var cardAndPurpose: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailRow("CARD") {
                HStack(spacing: 8) {
                    CardArt(width: 24, height: 16)
                    Text(details?.cardLabel ?? command?.cardLabel ?? "Shopping card •••• 4242")
                }
            }
            detailRow("FOR") {
                Text(details.map { "\($0.merchant) · \($0.reason)" } ?? "Shop · Something you asked for")
                    .lineLimit(3)
            }
        }
    }

    private func detailRow(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: typeSize.isAccessibilitySize ? nil : 52, alignment: .leading)
            value()
        }
    }

    @ViewBuilder
    private var status: some View {
        if case .unverified(let featureMissing) = state.lookup {
            VStack(alignment: .leading, spacing: 4) {
                Label("Crew can't verify this payment request.", systemImage: "exclamationmark.shield.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                if featureMissing {
                    Text("Update crew-push to pay from Crew.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else if command == nil {
            Label("Crew can't verify this payment request.", systemImage: "exclamationmark.shield.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
        } else if state.lookup == .failed {
            HStack(spacing: 8) {
                Label("Couldn't load the amount.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer(minLength: 8)
                Button("Try Again", action: retry)
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
            }
            .font(.footnote)
        } else {
            Text("\(request.requester ?? botName) states the amount and the shop. The card fills only on \(host).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minHeight: 0, alignment: .top)
                .clipped()
        }
        if let failure = state.failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var buttons: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button(role: .destructive) {
                respond(.deny)
            } label: {
                Text("Deny")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Deny payment")
            .disabled(state.isApproved)
            if !isUnverified {
                HoldToPayButton(
                    confirmation: details.map { String(localized: "Pay \($0.amount) at \(host)?") } ?? "",
                    warning: isPunycode(host) ? String(localized: "This address uses special characters and could imitate another site.") : nil,
                    isApproved: state.isApproved,
                    initialProgress: holdProgress
                ) {
                    respond(.once)
                }
                .disabled(details == nil)
            }
        }
        .buttonBorderShape(.capsule)
        .buttonSizing(.flexible)
        .controlSize(.large)
    }

    private var summary: Text {
        guard let details else { return Text("Payment request from \(request.requester ?? botName). Pay at \(host).") }
        let card = command?.last4.map { String(localized: "Card ending \($0).") } ?? "\(details.cardLabel)." 
        return Text("Payment request from \(request.requester ?? botName). Pay at \(host). \(details.merchant), \(details.reason). \(card) Total \(details.amount), as stated by \(request.requester ?? botName).")
    }

    private func countDown() async {
        guard let deadline else { return secondsLeft = nil }
        while !Task.isCancelled {
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else {
                secondsLeft = nil
                return expire()
            }
            let shown = Int(left.rounded(.up))
            let crossedMinute = shown <= 60 && (secondsLeft ?? 61) > 60
            let crossedFifteen = shown <= 15 && (secondsLeft ?? 16) > 15
            if crossedMinute || crossedFifteen {
                AccessibilityNotification.Announcement(shown <= 15 ? "15 seconds left to pay" : "1 minute left to pay").post()
            }
            withAnimation(.smooth) { secondsLeft = shown <= 60 ? shown : nil }
            let next = shown > 60 ? left - 60 : left - Double(shown - 1)
            try? await Task.sleep(for: .seconds(max(next, 0.05)))
        }
    }
}

private struct HoldToPayButton: View {
    let confirmation: String
    let warning: String?
    let isApproved: Bool
    var initialProgress = 0.0
    let pay: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var progress: Double
    @State private var pressedAt: Date?
    @State private var presses = 0
    @State private var confirming = false

    init(confirmation: String, warning: String?, isApproved: Bool, initialProgress: Double = 0, pay: @escaping () -> Void) {
        self.confirmation = confirmation
        self.warning = warning
        self.isApproved = isApproved
        self.pay = pay
        _progress = State(initialValue: initialProgress)
    }

    var body: some View {
        Button {
            if !isApproved { confirming = true }
        } label: {
            Group {
                if isApproved {
                    Label {
                        Text("Approved")
                    } icon: {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                            .transition(reduceMotion ? AnyTransition.identity : AnyTransition(.symbolEffect(.drawOn)))
                    }
                } else {
                    Text("Hold to Pay")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .overlay {
            GeometryReader { geometry in
                Rectangle()
                    .fill(.white.opacity(0.32))
                    .frame(width: geometry.size.width * (isApproved ? 1 : progress))
            }
            .clipShape(.capsule)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay {
            Color.clear
                .contentShape(.capsule)
                .onLongPressGesture(minimumDuration: 1, maximumDistance: 40) {
                    complete()
                } onPressingChanged: { pressing in
                    pressing ? press() : release()
                }
                .accessibilityHidden(true)
        }
        .scaleEffect(pressedAt != nil && !reduceMotion ? 0.97 : 1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: pressedAt != nil)
        .sensoryFeedback(.impact(weight: .light), trigger: presses)
        .sensoryFeedback(.success, trigger: isApproved) { old, new in !old && new }
        .onChange(of: isApproved) { _, approved in
            if !approved { progress = 0 }
        }
        .confirmationDialog(confirmation, isPresented: $confirming, titleVisibility: .visible) {
            Button("Pay") { approve() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let warning { Text(warning) }
        }
        .accessibilityLabel(isApproved ? "Approved" : "Hold to Pay")
        .accessibilityHint("Double-tap to confirm the payment.")
        .accessibilityAction(named: "Pay") { confirming = true }
    }

    private func press() {
        guard isEnabled, !isApproved else { return }
        pressedAt = .now
        presses += 1
        withAnimation(.linear(duration: 1)) { progress = 1 }
    }

    private func release() {
        guard let pressedAt, !isApproved else { return }
        self.pressedAt = nil
        let held = Date.now.timeIntervalSince(pressedAt)
        guard held >= 0.95 else { return springBack(confirming: held < 0.3) }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            if !isApproved { springBack(confirming: false) }
        }
    }

    private func springBack(confirming: Bool) {
        withAnimation(reduceMotion ? .linear(duration: 0.25) : .spring(duration: 0.25)) { progress = 0 }
        if confirming { self.confirming = true }
    }

    private func complete() {
        guard isEnabled, !isApproved else { return }
        pressedAt = nil
        approve()
    }

    private func approve() {
        withAnimation(.smooth) { progress = 1 }
        pay()
    }
}

struct CardArt: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 6)
            .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.78).opacity(0.8))
                    .frame(width: width * 0.2, height: height * 0.18)
                    .offset(x: width * 0.14, y: height * 0.36)
            }
            .overlay {
                RoundedRectangle(cornerRadius: height / 6)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

struct PaymentNoticeCard: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(text, systemImage: "creditcard")
                .font(.subheadline)
            Spacer(minLength: 8)
            Button("OK", action: dismiss)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
        .padding(16)
        .background { Color.clear.glassEffect(in: .rect(cornerRadius: 28)) }
    }
}

struct ShopOfferCard: View {
    let botName: String
    let host: String
    let notNow: () -> Void
    let addShop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("\(botName) needs a card for \(Text(host).fontWeight(.semibold))")
            } icon: {
                CardArt(width: 24, height: 16)
            }
            .font(.subheadline)
            if isPunycode(host) {
                Label("This address uses special characters and could imitate another site.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Only add sites you'd shop at yourself.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Not Now", action: notNow)
                    .buttonStyle(.bordered)
                Button("Add Shop…", action: addShop)
                    .buttonStyle(.borderedProminent)
            }
            .buttonBorderShape(.capsule)
            .buttonSizing(.flexible)
        }
        .padding(16)
        .background { Color.clear.glassEffect(in: .rect(cornerRadius: 28)) }
    }
}

struct PaymentReceiptRow: View {
    let receipt: PaymentReceipt

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "creditcard")
                .foregroundStyle(tint)
            Text(receipt.text)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(receipt.text)
    }

    private var tint: AnyShapeStyle {
        if receipt.tone == .approved { return AnyShapeStyle(.green) }
        if receipt.tone == .denied { return AnyShapeStyle(.red) }
        if receipt.tone == .warning { return AnyShapeStyle(.orange) }
        return AnyShapeStyle(.secondary)
    }

}
