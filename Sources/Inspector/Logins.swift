import SwiftUI

struct PasswordsTab: View {
    let bot: Bot
    let vault: BotVault
    let isBrowserOff: Bool
    let shops: ShopList?

    @Environment(Connection.self) private var connection

    var body: some View {
        LoginsCard(bot: bot, vault: vault, isBrowserOff: isBrowserOff)
        OnePasswordCard(bot: bot, vault: vault)
        if connection.supportsPayments {
            ShopsCard(bot: bot, isBrowserOff: isBrowserOff, fixture: shops)
        }
    }
}

extension Connection {
    var vaultLink: VaultLink? {
        guard Snapshot.requested == nil, state == .connected, let gateway, let server = session?.server else { return nil }
        return VaultLink(gateway: gateway, server: server, urlSession: urlSession)
    }
}

private struct LoginsCard: View {
    let bot: Bot
    let vault: BotVault
    let isBrowserOff: Bool

    @Environment(Connection.self) private var connection
    @State private var editing: LoginTarget?
    @State private var confirmingRemoval: Login?
    @State private var removing: Set<Login.ID> = []
    @State private var removeFailures: [Login.ID: String] = [:]
    @State private var highlighted: Set<Login.ID> = []

    private var isOnline: Bool {
        connection.state == .connected
    }

    var body: some View {
        Section {
            if vault.listFailed {
                HStack(spacing: 8) {
                    Text(vault.tokenSaved == true ? String(localized: "Couldn't load logins. 1Password may not accept \(bot.title)'s token.") : String(localized: "Couldn't load logins."))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Try Again") { reload() }
                        .buttonStyle(.borderless)
                        .disabled(!isOnline)
                }
            }
            if vault.items != nil {
                rows
                Button("Add Login…", systemImage: "plus.circle") { editing = LoginTarget(item: nil) }
                    .disabled(!isOnline || vault.listFailed)
            } else if !vault.listFailed {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("Logins")
        } footer: {
            if !footers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(footers, id: \.self) { Text($0) }
                }
            }
        }
        .sheet(item: $editing) { target in
            LoginSheet(bot: bot, vault: vault, editing: target.item) { id in highlight(id) }
        }
        .confirmationDialog(
            confirmingRemoval.map { String(localized: "Remove the login for \($0.title)?") } ?? "",
            isPresented: Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: confirmingRemoval
        ) { login in
            Button("Remove Login", role: .destructive) { remove(login) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("\(bot.title) can no longer sign in there with it.")
        }
    }

    @ViewBuilder
    private var rows: some View {
        let logins = vault.logins
        if logins.isEmpty {
            Text("\(bot.title) has no saved logins.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(logins) { row($0) }
        }
    }

    @ViewBuilder
    private func row(_ login: Login) -> some View {
        let content = LoginRow(login: login, isRemoving: removing.contains(login.id), failure: removeFailures[login.id], isHighlighted: highlighted.contains(login.id))
        if login.isLocal {
            Group {
                if login.canEdit {
                    Button { edit(login) } label: { content }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #else
                        .tint(.primary)
                        #endif
                } else {
                    content
                }
            }
            .contextMenu {
                if login.canEdit {
                    Button("Edit Login…", systemImage: "pencil") { editing = LoginTarget(item: login.item) }
                        .disabled(!isOnline)
                }
                Button("Remove Login…", systemImage: "trash", role: .destructive) { confirmingRemoval = login }
                    .disabled(!isOnline)
            }
            #if os(iOS)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Remove", systemImage: "trash") { confirmingRemoval = login }
                    .tint(.red)
                    .disabled(!isOnline)
            }
            #endif
            .accessibilityAction(named: "Edit Login") { edit(login) }
            .accessibilityAction(named: "Remove Login") { if isOnline { confirmingRemoval = login } }
        } else {
            content
        }
    }

    private func edit(_ login: Login) {
        guard login.canEdit, isOnline else { return }
        editing = LoginTarget(item: login.item)
    }

    private var footers: [String] {
        guard vault.items != nil else { return [] }
        var footers: [String] = []
        if !vault.logins.isEmpty { footers.append(String(localized: "\(bot.title) fills these only on their sites, and the passwords never enter the chat.")) }
        if isBrowserOff { footers.append(String(localized: "Turn on Browser in Capabilities so \(bot.title) can sign in.")) }
        if vault.isTerminalLocal { footers.append(String(localized: "Bots on this server run commands next to the vault, so a misbehaving bot could read these passwords.")) }
        return footers
    }

    private func reload() {
        guard let link = connection.vaultLink else { return }
        Task { await vault.load(link) }
    }

    private func remove(_ login: Login) {
        removing.insert(login.id)
        removeFailures[login.id] = nil
        Task {
            defer { removing.remove(login.id) }
            if await !vault.remove(login.item, via: connection.vaultLink) {
                removeFailures[login.id] = String(localized: "Couldn't remove this login. Try again.")
            }
        }
    }

    private func highlight(_ id: Login.ID) {
        withAnimation(.smooth) { highlighted = [id] }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth) { highlighted = [] }
        }
    }
}

private struct LoginTarget: Identifiable {
    let item: VaultItem?
    var id: String { item?.id ?? "new" }
}

private struct LoginRow: View {
    let login: Login
    let isRemoving: Bool
    let failure: String?
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(login.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let host = login.host, isPunycode(host) {
                    Label("Unusual address: check the spelling", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 0) {
                    Text(login.account)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ForEach(login.tags, id: \.self) { tag in
                        Text(verbatim: " · \(tag)")
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
}

private struct OnePasswordCard: View {
    let bot: Bot
    let vault: BotVault

    @Environment(Connection.self) private var connection
    @State private var isConnecting = false
    @State private var confirmingDisconnect = false
    @State private var isDisconnecting = false
    @State private var failure: String?

    private var status: OnePasswordStatus? {
        OnePasswordStatus(source: vault.onePassword, sourcesFailed: vault.sourcesFailed, envFailed: vault.envFailed, tokenSaved: vault.tokenSaved, listFailed: vault.listFailed, isDefault: bot.isDefault, bot: bot.title, terminalLocal: vault.isTerminalLocal)
    }

    private var isOnline: Bool {
        connection.state == .connected
    }

    var body: some View {
        Section {
            if let status {
                Label {
                    Text(status.title)
                } icon: {
                    Image(systemName: symbol(status.look))
                        .foregroundStyle(tint(status.look))
                }
                if let action = status.action {
                    button(action)
                }
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("1Password")
        } footer: {
            if let footnotes = status?.footnotes, !footnotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(footnotes, id: \.self) { Text($0) }
                }
            }
        }
        .sheet(isPresented: $isConnecting) {
            ConnectOnePasswordSheet(bot: bot, vault: vault)
        }
        .confirmationDialog("Disconnect 1Password from \(bot.title)?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive, action: disconnect)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(bot.title) can no longer sign in with its 1Password logins.")
        }
    }

    @ViewBuilder
    private func button(_ action: OnePasswordStatus.Action) -> some View {
        if action == .connect {
            Button("Connect…", systemImage: "link") { isConnecting = true }
                .disabled(!isOnline)
        } else if action == .retry {
            Button("Try Again") {
                guard let link = connection.vaultLink else { return }
                Task { await vault.load(link) }
            }
            .disabled(!isOnline)
        } else if isDisconnecting {
            ProgressView()
                .controlSize(.small)
        } else {
            Button("Disconnect…", systemImage: "minus.circle", role: .destructive) { confirmingDisconnect = true }
                .disabled(!isOnline)
        }
    }

    private func symbol(_ look: OnePasswordStatus.Look) -> String {
        if look == .connected { return "checkmark.circle.fill" }
        if look == .warning { return "exclamationmark.triangle.fill" }
        return "key.horizontal"
    }

    private func tint(_ look: OnePasswordStatus.Look) -> AnyShapeStyle {
        if look == .connected { return AnyShapeStyle(.green) }
        if look == .warning { return AnyShapeStyle(.orange) }
        return AnyShapeStyle(.secondary)
    }

    private func disconnect() {
        isDisconnecting = true
        failure = nil
        Task {
            defer { isDisconnecting = false }
            if await !vault.disconnect(via: connection.vaultLink) {
                failure = String(localized: "Couldn't disconnect 1Password. Try again.")
            }
        }
    }
}

struct LoginSheet: View {
    let bot: Bot
    let vault: BotVault
    let editing: VaultItem?
    let saved: (String) -> Void

    @Environment(Connection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var website: String
    @State private var username: String
    @State private var password = ""
    @State private var failure: String?
    @State private var isSaving = false
    @State private var visited: Set<LoginField>
    @FocusState private var focus: LoginField?

    init(bot: Bot, vault: BotVault, editing: VaultItem?, fixture: LoginEntry? = nil, failure: String? = nil, saved: @escaping (String) -> Void) {
        self.bot = bot
        self.vault = vault
        self.editing = editing
        self.saved = saved
        _website = State(initialValue: fixture?.website ?? editing?.origin.flatMap { URL(string: $0)?.host() } ?? "")
        _username = State(initialValue: fixture?.username ?? editing?.identifier ?? "")
        _password = State(initialValue: fixture?.password ?? "")
        _visited = State(initialValue: fixture == nil ? [] : Set(LoginField.allCases))
        _failure = State(initialValue: failure)
    }

    private var entry: LoginEntry {
        LoginEntry(website: website, username: username, password: password)
    }

    private var block: SecretBlock? {
        SecretBlock(server: connection.session?.server, isOnline: connection.state == .connected)
    }

    private var notice: String? {
        if let failure { return failure }
        if block == .http { return String(localized: "Saving a password needs an https connection to Hermes.") }
        return block == .offline ? String(localized: "You're offline.") : nil
    }

    private func problem(_ field: LoginField) -> String? {
        entry.problem(field, existing: vault.items ?? [], editing: editing, botTitle: bot.title)
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
                    field(.website, title: "Website") {
                        TextField("Website", text: $website, prompt: Text(verbatim: "www.example.com"))
                            #if os(iOS)
                            .keyboardType(.URL)
                            #endif
                    }
                    if let host = entry.host {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fills only on")
                                .foregroundStyle(.secondary)
                            Text(verbatim: "https://\(host)")
                                .fontWeight(.semibold)
                                .foregroundStyle(isPunycode(host) ? .orange : .primary)
                            if isPunycode(host) {
                                Label("This address uses special characters and could imitate another site.", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.footnote)
                    }
                    field(.username, title: "Username or Email") {
                        TextField("Username or Email", text: $username, prompt: Text("Required"))
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            #endif
                    }
                    field(.password, title: "Password") {
                        SecureField("Password", text: $password, prompt: Text("Required"))
                            #if os(iOS)
                            .textContentType(.password)
                            #endif
                    }
                } footer: {
                    Text(editing == nil
                        ? String(localized: "Crew sends the password once to your Hermes server, which keeps it encrypted in \(bot.title)'s vault. Crew doesn't store it.")
                        : String(localized: "Crew can't read the saved password, so enter it again. Crew sends it once to your Hermes server, which keeps it encrypted in \(bot.title)'s vault. Crew doesn't store it."))
                }
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            .privacySensitive()
            .onChange(of: focus) { previous, _ in
                if let previous { visited.insert(previous) }
            }
            .onChange(of: [website, username, password]) { failure = nil }
            .navigationTitle(editing == nil ? "Add Login" : "Edit Login")
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
                        Button(editing == nil ? "Add" : "Save", systemImage: "checkmark", role: .confirm, action: save)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .secretSheet(symbol: "key.fill")
    }

    private var canSave: Bool {
        entry.canSave(block: block, existing: vault.items ?? [], editing: editing)
    }

    private func field(_ field: LoginField, title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                content()
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .submitLabel(field == .password ? .done : .next)
                    #endif
                    .focused($focus, equals: field)
                    .onSubmit {
                        if field == .website { focus = .username } else if field == .username { focus = .password } else { save() }
                    }
            }
            if visited.contains(field), focus != field, let problem = problem(field) {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        let entry = entry
        password = ""
        visited.remove(.password)
        focus = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            guard let id = await vault.save(entry, replacing: editing, via: connection.vaultLink) else {
                failure = String(localized: "Couldn't save the login on the server.")
                return
            }
            saved(id)
            dismiss()
        }
    }
}

struct ConnectOnePasswordSheet: View {
    let bot: Bot
    let vault: BotVault

    @Environment(Connection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var failure: String?
    @State private var isSaving = false
    @State private var visited = false
    @FocusState private var isFocused: Bool

    init(bot: Bot, vault: BotVault, failure: String? = nil) {
        self.bot = bot
        self.vault = vault
        _failure = State(initialValue: failure)
    }

    private var block: SecretBlock? {
        SecretBlock(server: connection.session?.server, isOnline: connection.state == .connected)
    }

    private var notice: String? {
        if let failure { return failure }
        if block == .http { return String(localized: "Saving a token needs an https connection to Hermes.") }
        return block == .offline ? String(localized: "You're offline.") : nil
    }

    private var steps: [String] {
        var steps = [
            String(localized: "In 1Password, create a vault for \(bot.title), such as Crew · \(bot.title), and keep \(bot.title)'s logins there, each with its website."),
            String(localized: "On 1Password.com, open Developer > Service Accounts and create one that can only read that vault."),
        ]
        if vault.onePassword?.installed != true { steps.append(String(localized: "Install the 1Password CLI (op) in the Hermes environment on the server.")) }
        return steps + [String(localized: "Paste its token below.")]
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
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(index + 1, format: .number)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(step)
                        }
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        SecureField("Service Account Token", text: $token, prompt: Text(verbatim: "ops_…"))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .focused($isFocused)
                            .onSubmit(save)
                        if visited, !isFocused, !isServiceAccountToken(token) {
                            Text("Paste the token that starts with ops_.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Service Account Token")
                } footer: {
                    Text("Crew sends the token once to your Hermes server, which saves it in \(bot.title)'s settings. Crew doesn't store it.")
                }
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            .privacySensitive()
            .onChange(of: isFocused) { if !isFocused { visited = true } }
            .onChange(of: token) { failure = nil }
            .navigationTitle("Connect 1Password")
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
                        Button("Connect", systemImage: "checkmark", role: .confirm, action: save)
                            .disabled(!canConnect(token: token, block: block))
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .secretSheet(symbol: "key.fill")
    }

    private func save() {
        guard canConnect(token: token, block: block), !isSaving else { return }
        let value = token
        token = ""
        visited = false
        isSaving = true
        Task {
            defer { isSaving = false }
            if await vault.connect(token: value, via: connection.vaultLink) {
                dismiss()
            } else {
                failure = String(localized: "Couldn't save the token on the server.")
            }
        }
    }
}

extension View {
    func secretSheet(symbol: String, isCovered: Bool = false) -> some View {
        modifier(SecretSheet(symbol: symbol, isCovered: isCovered))
    }
}

private struct SecretSheet: ViewModifier {
    let symbol: String
    let isCovered: Bool

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .overlay {
                if isCovered || scenePhase != .active {
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        Image(systemName: symbol)
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        content
            .background(HiddenFromScreenCapture())
            .frame(width: 400)
            .frame(minHeight: 420)
        #endif
    }
}

#if os(macOS)
private struct HiddenFromScreenCapture: NSViewRepresentable {
    final class WindowWatcher: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard Snapshot.requested == nil else { return }
            window?.sharingType = .none
        }
    }

    func makeNSView(context: Context) -> NSView {
        WindowWatcher()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
