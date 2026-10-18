import SwiftUI

typealias CardSender = @MainActor ([String: String]) async throws -> MasterCard

struct ShopsCard: View {
    let bot: Bot
    let isBrowserOff: Bool

    @Environment(Connection.self) private var connection
    @State private var list: ShopList?
    @State private var loadFailed = false
    @State private var removing: Set<Shop.ID> = []
    @State private var removeFailures: [Shop.ID: String] = [:]
    @State private var isAdding = false
    @State private var isEditingCard = false
    @State private var isUpdating = false
    @State private var updateFailure: String?
    @State private var highlighted: Set<Shop.ID> = []
    private let sendCard: CardSender?

    init(bot: Bot, isBrowserOff: Bool, fixture: ShopList? = nil, updateFailure: String? = nil, sendCard: CardSender? = nil) {
        self.bot = bot
        self.isBrowserOff = isBrowserOff
        self.sendCard = sendCard
        _list = State(initialValue: fixture)
        _updateFailure = State(initialValue: updateFailure)
    }

    private var isOnline: Bool {
        connection.state == .connected
    }

    private func controls(_ list: ShopList) -> ShopsControls {
        ShopsControls(list: list, isOnline: isOnline, supportsCardEntry: connection.crewPush?.supportsCardEntry == true, hasCardVault: connection.crewPush?.hasCardVault == true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Card(title: "Shops") {
                if let list {
                    VStack(alignment: .leading, spacing: 12) {
                        cardRow(list.card, controls: controls(list))
                        Divider()
                        shopRows(list.shops)
                        if controls(list).showsUpdateShops {
                            Divider()
                            updateShopsRow(controls(list))
                        }
                        Divider()
                        Button("Add Shop…", systemImage: "plus.circle") { isAdding = true }
                            .buttonStyle(.borderless)
                            .disabled(!controls(list).canAddShop)
                    }
                } else if loadFailed {
                    HStack(spacing: 8) {
                        Text("Couldn't load shops.")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.borderless)
                            .disabled(!isOnline)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            ForEach(footers, id: \.text) { footer in
                Text(footer.text)
                    .font(.footnote)
                    .foregroundStyle(footer.isAlert ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 12)
            }
        }
        .task(id: isOnline) {
            guard isOnline, Snapshot.requested == nil else { return }
            await load()
        }
        .sheet(isPresented: $isAdding) {
            AddShopSheet(profile: bot.name) { shop in
                list?.shops.removeAll { $0.id == shop.id }
                list?.shops.append(shop)
                highlight([shop.id])
            }
        }
        .sheet(isPresented: $isEditingCard) {
            CardSheet(currentLabel: list.flatMap { controls($0).hasCard ? $0.card.label : nil }, send: sendCard) { card in
                list?.card = card
                guard Snapshot.requested == nil else { return }
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private func cardRow(_ card: MasterCard, controls: ShopsControls) -> some View {
        if let label = card.label, controls.hasCard {
            VStack(alignment: .leading, spacing: 4) {
                if controls.hasCardVault {
                    Text("Card used for new shops")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    CardArt(width: 40, height: 26)
                    HStack(spacing: 4) {
                        Text(label)
                            .lineLimit(1)
                        Text(verbatim: "•••• \(card.last4 ?? "")")
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                }
                if bot.isDefault, !controls.hasCardVault {
                    Text("Kept here, never used to pay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if controls.showsCardButton {
                    Button("Replace Card…", systemImage: "creditcard") { isEditingCard = true }
                        .buttonStyle(.borderless)
                        .disabled(!controls.canEditCard)
                        .padding(.top, 4)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(card.problem == "several" ? "More than one card on the server" : "No card on the server", systemImage: "creditcard.trianglebadge.exclamationmark")
                    .symbolRenderingMode(.multicolor)
                Text(controls.noCardText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if controls.showsCardButton {
                    Button("Add Card…", systemImage: "plus.circle") { isEditingCard = true }
                        .buttonStyle(.borderless)
                        .disabled(!controls.canEditCard)
                }
            }
        }
    }

    private func updateShopsRow(_ controls: ShopsControls) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isUpdating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Update Shops", systemImage: "arrow.triangle.2.circlepath", action: updateShops)
                    .buttonStyle(.borderless)
                    .disabled(!controls.canUpdateShops)
            }
            Text(controls.staleText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let updateFailure {
                Text(updateFailure)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func shopRows(_ shops: [Shop]) -> some View {
        if shops.isEmpty {
            Text("\(bot.title) can't pay anywhere yet.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shops) { shop in
                    if shop.id != shops.first?.id {
                        Divider()
                    }
                    ShopRow(shop: shop, isRemoving: removing.contains(shop.id), failure: removeFailures[shop.id], isHighlighted: highlighted.contains(shop.id))
                        .contextMenu {
                            Button("Remove Shop", systemImage: "trash", role: .destructive) { remove(shop) }
                                .disabled(!isOnline)
                        }
                        .accessibilityAction(named: "Remove Shop") { remove(shop) }
                }
            }
        }
    }

    private var footers: [(text: String, isAlert: Bool)] {
        guard let list else { return [] }
        var footers: [(text: String, isAlert: Bool)] = []
        if !list.shops.isEmpty { footers.append((String(localized: "\(bot.title) pays only on these sites, and asks you every time."), false)) }
        if isBrowserOff { footers.append((String(localized: "Turn on Browser in Capabilities so \(bot.title) can shop."), false)) }
        if (list.terminalBackend ?? "local") == "local" {
            footers.append((String(localized: "Bots on this server run commands next to the card, so a misbehaving bot could read it. Keep the card's limit low."), false))
        }
        if bot.isDefault, let leftover = list.legacyCards, leftover > 0 {
            footers.append((leftover == 1 ? String(localized: "1 older card is still in this bot's vault, and the bot can see it there. Remove it on the server.") : String(localized: "\(leftover) older cards are still in this bot's vault, and the bot can see them there. Remove them on the server."), false))
        }
        if list.gate == false { footers.append((String(localized: "Payments are off: this server has no dashboard login."), true)) }
        return footers
    }

    private func load() async {
        guard let server = connection.session?.server else { return }
        do {
            list = try await paymentsCall("payments", query: [URLQueryItem(name: "profile", value: bot.name)], on: server, with: connection.urlSession, as: ShopList.self)
            loadFailed = false
        } catch {
            loadFailed = list == nil
        }
    }

    private func remove(_ shop: Shop) {
        guard let server = connection.session?.server else { return }
        removing.insert(shop.id)
        removeFailures[shop.id] = nil
        Task {
            defer { removing.remove(shop.id) }
            do {
                _ = try await paymentsCall("payments/shops/\(shop.id)", query: [URLQueryItem(name: "profile", value: bot.name)], method: "DELETE", on: server, with: connection.urlSession, as: JSONValue.self)
            } catch let error as PaymentsError where error.code == "unknown_shop" {
            } catch {
                removeFailures[shop.id] = String(localized: "Couldn't remove this shop. Try again.")
                return
            }
            withAnimation(.smooth) { list?.shops.removeAll { $0.id == shop.id } }
        }
    }

    private func updateShops() {
        guard let server = connection.session?.server, !isUpdating else { return }
        let before = Set(list?.shops.map(\.id) ?? [])
        isUpdating = true
        updateFailure = nil
        Task {
            defer { isUpdating = false }
            do {
                let updated = try await paymentsCall("payments/shops/update", body: ["profile": bot.name], on: server, with: connection.urlSession, as: ShopsUpdated.self)
                list?.shops = updated.shops
                highlight(Set(updated.shops.map(\.id)).subtracting(before))
            } catch {
                updateFailure = (error as? PaymentsError)?.code == "payment_pending" ? String(localized: "Finish or deny the waiting payment first.") : String(localized: "Couldn't update shops. Try again.")
                await load()
            }
        }
    }

    private func highlight(_ ids: Set<Shop.ID>) {
        withAnimation(.smooth) { highlighted = ids }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth) { highlighted = [] }
        }
    }
}

private struct ShopRow: View {
    let shop: Shop
    let isRemoving: Bool
    let failure: String?
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shop.host)
                if shop.punycode || isPunycode(shop.host) {
                    Label("Unusual address: check the spelling", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Text(dateLine)
                        .foregroundStyle(.secondary)
                    if shop.stale {
                        Text("Old card")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.subheadline)
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            if isRemoving {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.tint.opacity(isHighlighted ? 0.16 : 0), in: .rect(cornerRadius: 8))
        .padding(.horizontal, -8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var dateLine: String {
        if let paid = shop.lastPaidAt {
            return String(localized: "Last paid \(Date(timeIntervalSince1970: paid).formatted(.dateTime.day().month(.abbreviated)))")
        }
        return String(localized: "Added \(Date(timeIntervalSince1970: shop.createdAt).formatted(.dateTime.day().month(.abbreviated)))")
    }
}

struct AddShopSheet: View {
    let profile: String
    let alreadyAdded: ((String) -> Void)?
    let added: (Shop) -> Void

    @Environment(Connection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var failure: String?
    @State private var isSaving = false

    init(profile: String, site: String = "", failure: String? = nil, alreadyAdded: ((String) -> Void)? = nil, added: @escaping (Shop) -> Void) {
        self.profile = profile
        self.alreadyAdded = alreadyAdded
        self.added = added
        _input = State(initialValue: site)
        _failure = State(initialValue: failure)
    }

    private var host: String? {
        shopHost(from: input)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Website", text: $input, prompt: Text(verbatim: "www.zalando.se"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(add)
                        .onChange(of: input) { failure = nil }
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 12) {
                        if let host {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("The card will fill only on")
                                Text(verbatim: "https://\(host)")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(isPunycode(host) ? .orange : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if isPunycode(host) {
                                Label("This address uses special characters and could imitate another site.", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(String(localized: "Use the address shown at checkout; www.zalando.se and zalando.se are different sites. Only add sites you'd shop at yourself."))
                    }
                    .padding(.top, 8)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Shop")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add", systemImage: "checkmark", role: .confirm, action: add)
                            .disabled(host == nil || connection.state != .connected)
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 360)
        .frame(minHeight: 280)
        #endif
    }

    private func add() {
        guard let host, let server = connection.session?.server, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let created = try await paymentsCall("payments/shops", body: ["profile": profile, "site": input.trimmingCharacters(in: .whitespacesAndNewlines)], on: server, with: connection.urlSession, as: ShopCreated.self)
                added(created.shop)
                dismiss()
            } catch let error as PaymentsError where error.code == "duplicate_shop" && alreadyAdded != nil {
                alreadyAdded?("https://\(host)")
                dismiss()
            } catch let error as PaymentsError {
                failure = error.message(host: host)
            } catch {
                failure = String(localized: "Couldn't reach Hermes. Try again.")
            }
        }
    }
}

struct CardSheet: View {
    let currentLabel: String?
    let send: CardSender?
    let saved: (MasterCard) -> Void

    @Environment(Connection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var number: String
    @State private var expiry: String
    @State private var cvc: String
    @State private var name = ""
    @State private var label: String
    @State private var failure: String?
    @State private var isSaving = false
    @State private var visited: Set<CardField>
    @State private var isCovered: Bool
    @FocusState private var focus: CardField?

    init(currentLabel: String?, send: CardSender? = nil, fixture: CardEntry? = nil, failure: String? = nil, isCovered: Bool = false, saved: @escaping (MasterCard) -> Void) {
        self.currentLabel = currentLabel
        self.send = send
        self.saved = saved
        _number = State(initialValue: fixture?.number ?? "")
        _expiry = State(initialValue: fixture?.expiry ?? "")
        _cvc = State(initialValue: fixture?.cvc ?? "")
        _label = State(initialValue: fixture?.label ?? currentLabel ?? String(localized: "Shopping card"))
        _visited = State(initialValue: fixture == nil ? [] : Set(CardField.allCases))
        _failure = State(initialValue: failure)
        _isCovered = State(initialValue: isCovered)
    }

    private var entry: CardEntry {
        CardEntry(number: number, expiry: expiry, cvc: cvc, name: name, label: label)
    }

    private var isHTTPS: Bool {
        connection.session?.server.scheme?.lowercased() == "https"
    }

    private var notice: String? {
        if let failure { return failure }
        if !isHTTPS { return String(localized: "Adding a card needs an https connection to Hermes.") }
        if connection.state != .connected { return String(localized: "You're offline.") }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section {
                        Label(notice, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    field(.number, title: "Card Number") {
                        TextField("Card Number", text: $number, prompt: Text(verbatim: "1234 5678 9012 3456"))
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .textContentType(.creditCardNumber)
                            #endif
                    }
                    field(.expiry, title: "Expiry") {
                        TextField("Expiry", text: $expiry, prompt: Text(verbatim: "MM/YY"))
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .textContentType(.creditCardExpiration)
                            #endif
                    }
                    field(.cvc, title: "Security Code") {
                        SecureField("Security Code", text: $cvc, prompt: Text(verbatim: "CVC"))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .textContentType(.creditCardSecurityCode)
                            #endif
                    }
                    field(.name, title: "Name on Card") {
                        TextField("Name on Card", text: $name, prompt: Text("Optional"))
                            #if os(iOS)
                            .textContentType(.creditCardName)
                            #endif
                    }
                } footer: {
                    Text(currentLabel == nil
                        ? String(localized: "Crew sends the card once to your Hermes server, which keeps it encrypted. Crew doesn't store it, and bots never see the number.")
                        : String(localized: "Crew sends the card once to your Hermes server, which keeps it encrypted. Crew doesn't store it, and bots never see the number. Each bot's shops keep the old card until you update them in its Shops card."))
                }
                Section {
                    field(.label, title: "Label") {
                        TextField("Label", text: $label, prompt: Text("Shopping card"))
                    }
                } footer: {
                    Text("Shown in Crew and to bots with the last four digits, such as Shopping card •••• 4242.")
                }
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            .privacySensitive()
            .onChange(of: number) {
                let formatted = CardEntry.formattedNumber(number)
                if formatted != number { number = formatted }
                if entry.isNumberComplete, focus == .number { focus = .expiry }
            }
            .onChange(of: expiry) {
                let formatted = CardEntry.formattedExpiry(expiry)
                if formatted != expiry { expiry = formatted }
                if expiry.count >= 5, entry.problem(.expiry) == nil, focus == .expiry { focus = .cvc }
            }
            .onChange(of: focus) { previous, _ in
                if let previous { visited.insert(previous) }
            }
            .onChange(of: [number, expiry, cvc, name, label]) { failure = nil }
            .navigationTitle(currentLabel == nil ? "Add Card" : "Replace Card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(currentLabel == nil ? "Add" : "Replace", systemImage: "checkmark", role: .confirm, action: save)
                            .disabled(!entry.isValid() || !isHTTPS || connection.state != .connected)
                    }
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if let next = focus.flatMap(nextField) {
                        Button("Next") { focus = next }
                    }
                    Button("Done") { focus = nil }
                }
                #endif
            }
        }
        .interactiveDismissDisabled(isSaving)
        .secretSheet(symbol: "creditcard", isCovered: isCovered)
    }

    private func field(_ field: CardField, title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                content()
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(field == .name ? .words : .never)
                    #endif
                    .focused($focus, equals: field)
                    #if os(iOS)
                    .submitLabel(field == .label ? .done : .next)
                    #endif
                    .onSubmit {
                        if let next = nextField(after: field) { focus = next } else { save() }
                    }
            }
            if visited.contains(field), focus != field, let problem = entry.problem(field) {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func nextField(after field: CardField) -> CardField? {
        CardField.allCases.firstIndex(of: field).flatMap { CardField.allCases.dropFirst($0 + 1).first }
    }

    private func save() {
        guard let server = connection.session?.server, isHTTPS, connection.state == .connected, entry.isValid(), !isSaving else { return }
        let body = entry.body
        number = ""
        expiry = ""
        cvc = ""
        name = ""
        visited = []
        focus = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let card = if let send { try await send(body) } else {
                    try await paymentsCall("payments/card", method: "PUT", body: body, on: server, with: connection.urlSession, as: CardSet.self).card
                }
                saved(card)
                dismiss()
            } catch let error as PaymentsError {
                failure = error.message(host: nil)
            } catch {
                failure = String(localized: "Couldn't reach Hermes. Try again.")
            }
        }
    }
}
