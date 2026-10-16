import SwiftUI

struct ShopsCard: View {
    let bot: Bot
    let isBrowserOff: Bool

    @Environment(Connection.self) private var connection
    @State private var list: ShopList?
    @State private var loadFailed = false
    @State private var removing: Set<Shop.ID> = []
    @State private var removeFailures: [Shop.ID: String] = [:]
    @State private var isAdding = false
    @State private var highlighted: Shop.ID?

    init(bot: Bot, isBrowserOff: Bool, fixture: ShopList? = nil) {
        self.bot = bot
        self.isBrowserOff = isBrowserOff
        _list = State(initialValue: fixture)
    }

    private var isOnline: Bool {
        connection.state == .connected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Card(title: "Shops") {
                if let list {
                    VStack(alignment: .leading, spacing: 12) {
                        cardRow(list.card)
                        Divider()
                        shopRows(list.shops)
                        Divider()
                        Button("Add Shop…", systemImage: "plus.circle") { isAdding = true }
                            .buttonStyle(.borderless)
                            .disabled(list.card.problem != nil || list.card.label == nil || !isOnline)
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
                highlight(shop.id)
            }
        }
    }

    @ViewBuilder
    private func cardRow(_ card: MasterCard) -> some View {
        if let label = card.label, card.problem == nil {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    CardArt(width: 40, height: 26)
                    Text("\(label) •••• \(card.last4 ?? "")")
                }
                if bot.isDefault {
                    Text("Kept here, never used to pay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(card.problem == "several" ? "More than one card on the server" : "No card on the server", systemImage: "creditcard.trianglebadge.exclamationmark")
                    .symbolRenderingMode(.multicolor)
                Text(card.problem == "several" ? "Keep one card without a website; Crew can't tell which to use." : "Add one card on the server without a website. Crew copies it to each shop you add.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if card.problem != "several" {
                    Button("Copy Setup Command", systemImage: "doc.on.doc") { copySetupCommand() }
                        .buttonStyle(.borderless)
                }
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
                    ShopRow(shop: shop, isRemoving: removing.contains(shop.id), failure: removeFailures[shop.id], isHighlighted: highlighted == shop.id)
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

    private func highlight(_ id: Shop.ID) {
        withAnimation(.smooth) { highlighted = id }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth) { highlighted = nil }
        }
    }

    private func copySetupCommand() {
        #if os(iOS)
        UIPasteboard.general.string = "hermes vault add"
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("hermes vault add", forType: .string)
        #endif
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
    let added: (Shop) -> Void

    @Environment(Connection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var failure: String?
    @State private var isSaving = false

    init(profile: String, site: String = "", failure: String? = nil, added: @escaping (Shop) -> Void) {
        self.profile = profile
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
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add", action: add)
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
            } catch let error as PaymentsError {
                failure = error.message(host: host)
            } catch {
                failure = String(localized: "Couldn't reach Hermes. Try again.")
            }
        }
    }
}
