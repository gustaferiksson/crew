import AuthenticationServices
import SwiftUI

struct ConnectionsSection: View {
    let bot: Bot
    let store: BotConnections
    @Binding var isAdding: Bool
    @Binding var opened: MCPServer?

    @Environment(Connection.self) private var connection
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var confirmingRemoval: MCPServer?

    private var isOnline: Bool {
        connection.state == .connected
    }

    var body: some View {
        Section {
            if store.loadFailed {
                HStack(spacing: 8) {
                    Text("Couldn't load connections.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Try Again") { run { server, urlSession in await store.load(on: server, with: urlSession) } }
                        .buttonStyle(.borderless)
                        .disabled(!isOnline)
                }
            } else if let servers = store.servers {
                if servers.isEmpty {
                    Text("\(bot.title) has no connections.")
                        .foregroundStyle(.secondary)
                }
                ForEach(servers) { row($0) }
                Button("Add Connection…", systemImage: "plus.circle") { isAdding = true }
                    .disabled(!isOnline)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("Connections")
        } footer: {
            Text("Tools from other apps and services that \(bot.title) can use. Changes apply to new chats.")
        }
        .confirmationDialog(
            confirmingRemoval.map { String(localized: "Remove \(connectionLooks[$0.name]?.title ?? $0.name) from \(bot.title)?") } ?? "",
            isPresented: Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: confirmingRemoval
        ) { server in
            Button("Remove", role: .destructive) { run { url, urlSession in await store.remove(server.name, on: url, with: urlSession) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("\(bot.title) loses these tools in new chats.")
        }
    }

    private func row(_ server: MCPServer) -> some View {
        let status = store.status(of: server)
        let isEditable = server.source != "plugin"
        let error: String? = if let failure = store.failures[server.id] { failure } else if case .failed(let message) = status { message } else { nil }
        return ConnectionRow(
            server: server,
            status: status,
            isBusy: store.busy.contains(server.id),
            failure: store.failures[server.id],
            isOnline: isOnline,
            enabled: Binding(get: { server.enabled }, set: { value in run { url, urlSession in await store.setEnabled(value, for: server.name, on: url, with: urlSession) } }),
            signIn: { signIn(server) },
            cancelSignIn: { run { url, urlSession in await store.cancelSignIn(server.name, on: url, with: urlSession) } },
            showDetails: { opened = server }
        )
        .help(error ?? "")
        .contextMenu {
            Section {
                Button("Show Details", systemImage: "info.circle") { opened = server }
                Button("Test", systemImage: "checkmark.circle") { test(server) }
                    .disabled(!isOnline || !server.enabled)
                if server.auth == "oauth", isEditable {
                    Button("Sign In…", systemImage: "person.badge.key") { signIn(server) }
                        .disabled(!isOnline || status == .signingIn)
                }
                if isEditable {
                    Button("Remove…", systemImage: "trash", role: .destructive) { confirmingRemoval = server }
                        .disabled(!isOnline)
                }
            } header: {
                if let error { Text(error) }
            }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isEditable {
                Button("Remove", systemImage: "trash") { confirmingRemoval = server }
                    .tint(.red)
                    .disabled(!isOnline)
            }
        }
        #endif
        .accessibilityAction(named: "Show Details") { opened = server }
        .accessibilityAction(named: "Test") { test(server) }
    }

    private func test(_ server: MCPServer) {
        run { url, urlSession in await store.test(server.name, on: url, with: urlSession) }
    }

    private func signIn(_ server: MCPServer) {
        let webAuthenticationSession = webAuthenticationSession
        run { url, urlSession in
            await store.signIn(server.name, on: url, with: urlSession) { authorization in
                _ = try await webAuthenticationSession.authenticate(using: authorization, callback: .customScheme("crew-connections"), preferredBrowserSession: .shared, additionalHeaderFields: [:])
            }
        }
    }

    private func run(_ action: @escaping (URL, URLSession) async -> Void) {
        guard let server = connection.session?.server else { return }
        let urlSession = connection.urlSession
        Task { await action(server, urlSession) }
    }
}

private struct ConnectionRow: View {
    let server: MCPServer
    let status: ConnectionStatus
    let isBusy: Bool
    let failure: String?
    let isOnline: Bool
    @Binding var enabled: Bool
    let signIn: () -> Void
    let cancelSignIn: () -> Void
    let showDetails: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConnectionIcon(name: server.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionLooks[server.name]?.title ?? server.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ConnectionStatusLine(status: status, errorLines: 2)
                    .font(.subheadline)
                if status == .signingIn {
                    Button("Cancel", action: cancelSignIn)
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                } else if case .needsSignIn = status {
                    Button("Sign In", action: signIn)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .disabled(!isOnline || isBusy)
                }
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if isBusy || status == .signingIn || status == .checking {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Show Details", systemImage: "info.circle", action: showDetails)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
            if let plugin = server.plugin {
                Text("From \(plugin)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Enabled", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!isOnline || isBusy || status == .signingIn)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ConnectionStatusLine: View {
    let status: ConnectionStatus
    let errorLines: Int?

    var body: some View {
        if status == .off {
            Text("Off").foregroundStyle(.secondary)
        } else if status == .checking {
            Text("Checking…").foregroundStyle(.secondary)
        } else if status == .signingIn {
            Text("Waiting for sign-in…").foregroundStyle(.secondary)
        } else if case .connected(let tools) = status {
            Text("Connected · ^[\(tools) tool](inflect: true)").foregroundStyle(.secondary)
        } else if case .needsSignIn = status {
            Text("Needs Sign-In").foregroundStyle(.orange)
        } else if case .failed(let message) = status {
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(errorLines)
        }
    }
}

struct ConnectionIcon: View {
    let name: String

    private static let colors: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .cyan]
    private static let tints: [ConnectionCategory: Color] = [.productivity: .blue, .developer: .indigo, .data: .teal, .business: .green, .design: .pink, .reference: .orange, .travel: .cyan]

    var body: some View {
        let look = connectionLooks[name]
        Group {
            if let look {
                Image(systemName: look.symbol)
            } else {
                Text(name.prefix(1).uppercased())
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background((look.flatMap { Self.tints[$0.category] } ?? Self.colors[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count]).gradient, in: .rect(cornerRadius: 7))
        .accessibilityHidden(true)
    }
}

struct AddConnectionSheet: View {
    let bot: Bot
    let store: BotConnections

    @Environment(Connection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let sections = gallerySections(catalog: store.catalog ?? [], servers: store.servers ?? [], query: query)
        NavigationStack {
            Form {
                #if os(macOS)
                Section {
                    TextField(text: $query, prompt: Text("Search")) {
                        Image(systemName: "magnifyingglass")
                    }
                    .multilineTextAlignment(.leading)
                }
                #endif
                Section {
                    NavigationLink {
                        CustomConnectionForm(store: store) { dismiss() }
                    } label: {
                        Label("Custom Connection", systemImage: "plus.square.dashed")
                    }
                } footer: {
                    Text("A server's address, or a command the server runs.")
                }
                if let catalog = store.catalog, !catalog.isEmpty {
                    if sections.isEmpty {
                        Section {
                        } header: {
                            Text("No Results for “\(query)”")
                        }
                    }
                    ForEach(sections, id: \.category) { section in
                        Section(section.category.rawValue) {
                            ForEach(section.entries) { entry in
                                NavigationLink {
                                    CatalogEntryForm(entry: entry, store: store) { dismiss() }
                                } label: {
                                    CatalogRow(entry: entry)
                                }
                                .disabled(entry.installed)
                            }
                        }
                    }
                } else if store.catalog != nil || store.catalogFailed {
                    Section {
                        HStack(spacing: 8) {
                            Text("Couldn't load the catalog.")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button("Try Again") { loadCatalog() }
                                .buttonStyle(.borderless)
                                .disabled(connection.state != .connected)
                        }
                    }
                } else {
                    Section {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)
            #if os(iOS)
            .searchable(text: $query, prompt: Text("Search"))
            #endif
            .navigationTitle("Add Connection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
            .task { loadCatalog() }
        }
        #if os(macOS)
        .frame(width: 420, height: 560)
        #endif
    }

    private func loadCatalog() {
        guard let server = connection.session?.server else { return }
        let urlSession = connection.urlSession
        Task { await store.loadCatalog(on: server, with: urlSession) }
    }
}

private struct CatalogRow: View {
    let entry: MCPCatalogEntry

    var body: some View {
        HStack(spacing: 12) {
            ConnectionIcon(name: entry.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionLooks[entry.name]?.title ?? entry.name)
                    .lineLimit(1)
                Text(entry.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if entry.installed {
                Text("Added")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CatalogEntryForm: View {
    let entry: MCPCatalogEntry
    let store: BotConnections
    let done: () -> Void

    @Environment(Connection.self) private var connection
    @State private var values: [String: String] = [:]
    @State private var token = ""
    @State private var failure: String?
    @State private var isSaving = false

    private var title: String {
        connectionLooks[entry.name]?.title ?? entry.name
    }

    private var isExtra: Bool {
        !(store.catalog ?? []).contains { $0.name == entry.name }
    }

    private var isComplete: Bool {
        entry.requiredEnv.allSatisfy { !$0.required || !(values[$0.name] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            && (!isExtra || entry.authType != "header" || !token.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ConnectionIcon(name: entry.name)
                    Text(title)
                        .font(.headline)
                }
                Text(entry.description)
            }
            Section {
                LabeledContent(entry.url == nil ? "Command" : "Address") {
                    Text(entry.url ?? ([entry.command ?? ""] + entry.args).joined(separator: " "))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            } footer: {
                Text(entry.authType == "oauth" ? "After adding it, sign in from the Connections list." : entry.authType == "header" ? "Sent as a bearer token. Hermes keeps it in the bot's secrets." : "No sign-in needed.")
            }
            if isExtra, entry.authType == "header" {
                Section {
                    SecureField("API Key", text: $token, prompt: Text("Personal Access Token"))
                    if let page = connectionLooks[entry.name]?.tokenPage {
                        Link("Create a Token on \(title)", destination: page)
                    }
                } footer: {
                    Text("Choose the repositories and permissions it may use, such as Contents, Issues and Pull requests.")
                }
            }
            if !entry.requiredEnv.isEmpty {
                Section("Details") {
                    ForEach(entry.requiredEnv, id: \.name) { spec in
                        let value = Binding(get: { values[spec.name] ?? "" }, set: { values[spec.name] = $0 })
                        VStack(alignment: .leading, spacing: 4) {
                            Text(spec.prompt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Group {
                                if spec.isSecret {
                                    SecureField(spec.name, text: value)
                                } else {
                                    TextField(spec.name, text: value)
                                }
                            }
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        }
                    }
                }
            }
            if !entry.postInstall.isEmpty {
                Section {
                    DisclosureGroup("Setup Notes") {
                        Text(entry.postInstall.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .privacySensitive()
        .disabled(isSaving)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Add", systemImage: "checkmark", role: .confirm, action: add)
                        .disabled(!isComplete || connection.state != .connected)
                }
            }
        }
    }

    private func add() {
        guard let server = connection.session?.server, !isSaving else { return }
        let env = values.filter { !$0.value.isEmpty }.mapValues(JSONValue.string)
        let extra = CustomConnection(name: entry.name, kind: .url, url: entry.url ?? "", auth: entry.authType == "header" ? .apiKey : .signIn, token: token)
        guard let body = isExtra ? extra.body : ["name": .string(entry.name), "env": .object(env)] else { return }
        isSaving = true
        failure = nil
        Task {
            defer { isSaving = false }
            do {
                try await store.add(body, catalog: !isExtra, on: server, with: connection.urlSession)
                done()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

struct CustomConnectionForm: View {
    let store: BotConnections
    let done: () -> Void

    @Environment(Connection.self) private var connection
    @State private var entry: CustomConnection
    @State private var failure: String?
    @State private var isSaving = false

    init(store: BotConnections, entry: CustomConnection = CustomConnection(), done: @escaping () -> Void) {
        self.store = store
        self.done = done
        _entry = State(initialValue: entry)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $entry.name, prompt: Text("Name"))
                    .autocorrectionDisabled()
                Picker("Type", selection: $entry.kind) {
                    Text("Address").tag(CustomConnection.Kind.url)
                    Text("Command").tag(CustomConnection.Kind.command)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if entry.kind == .url {
                Section {
                    TextField("Address", text: $entry.url, prompt: Text(verbatim: "https://example.com/mcp"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    Picker("Sign-In", selection: $entry.auth) {
                        Text("None").tag(CustomConnection.Auth.none)
                        Text("API Key").tag(CustomConnection.Auth.apiKey)
                        Text("Sign In").tag(CustomConnection.Auth.signIn)
                    }
                    if entry.auth == .apiKey {
                        SecureField("API Key", text: $entry.token, prompt: Text("API Key"))
                    }
                } footer: {
                    Text(entry.auth == .signIn ? "After adding it, sign in from the Connections list." : entry.auth == .apiKey ? "Sent as a bearer token. Hermes keeps it in the bot's secrets." : "For servers that need no sign-in.")
                }
            } else {
                Section {
                    TextField("Command", text: $entry.command, prompt: Text(verbatim: "npx"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Arguments", text: $entry.arguments, prompt: Text("Arguments, one per line"), axis: .vertical)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } footer: {
                    Text("Runs on the Hermes server, not on this device.")
                }
                Section {
                    TextField("Environment", text: $entry.environment, prompt: Text(verbatim: "NAME=value"), axis: .vertical)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Environment")
                } footer: {
                    Text("One variable per line. Saved in the bot's settings on the server.")
                }
            }
            if let message = failure ?? (entry.name.isEmpty ? nil : entry.problem) {
                Section {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                }
            }
        }
        .formStyle(.grouped)
        .privacySensitive()
        .disabled(isSaving)
        .onChange(of: entry) { failure = nil }
        .navigationTitle("Custom Connection")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Add", systemImage: "checkmark", role: .confirm, action: add)
                        .disabled(entry.body == nil || connection.state != .connected)
                }
            }
        }
    }

    private func add() {
        guard let server = connection.session?.server, let body = entry.body, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await store.add(body, catalog: false, on: server, with: connection.urlSession)
                done()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
