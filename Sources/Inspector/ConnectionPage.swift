import AuthenticationServices
import SwiftUI

struct ConnectionPage: View {
    let bot: Bot
    let name: String
    let store: BotConnections

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isChangingAddress = false
    @State private var address = ""
    @State private var isChangingKey = false
    @State private var apiKey = ""
    @State private var isRemoving = false
    @State private var isAddingToBots = false

    private var isOnline: Bool {
        connection.state == .connected
    }

    private var tools: [MCPTool] {
        store.tests[name].flatMap { $0.ok ? $0.tools : nil } ?? []
    }

    private var isSearchable: Bool {
        tools.count > 20
    }

    var body: some View {
        Group {
            if let server = store.servers?.first(where: { $0.name == name }) {
                if isSearchable {
                    form(server)
                        #if os(iOS)
                        .searchable(text: $query, prompt: Text("Search Tools"))
                        #endif
                } else {
                    form(server)
                }
            } else {
                ContentUnavailableView("Connection Removed", systemImage: "puzzlepiece.extension", description: Text("This connection was removed."))
            }
        }
        .navigationTitle(connectionLooks[name]?.title ?? name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func form(_ server: MCPServer) -> some View {
        let status = store.status(of: server)
        let isBusy = store.busy.contains(server.id)
        let canEdit = isOnline && !isBusy && status != .signingIn && server.plugin == nil
        return Form {
            Section {
                HStack(spacing: 12) {
                    ConnectionIcon(name: server.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionLooks[server.name]?.title ?? server.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        ConnectionStatusLine(status: status, errorLines: nil)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section("Details") {
                if let plugin = server.plugin {
                    LabeledContent("Provided By", value: plugin)
                } else {
                    Toggle("Enabled", isOn: Binding(get: { server.enabled }, set: { value in run { url, urlSession in await store.setEnabled(value, for: server.name, on: url, with: urlSession) } }))
                        .disabled(!isOnline || isBusy || status == .signingIn)
                }
                if let look = connectionLooks[server.name], look.title != server.name {
                    LabeledContent("Name", value: server.name)
                }
                LabeledContent(server.url == nil ? "Command" : "Address") {
                    Text(server.address)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Sign-In") {
                    Text(server.auth == "oauth" ? "Sign In" : server.auth == "header" ? "API Key" : "None")
                }
                if server.plugin == nil, let url = server.url {
                    Button("Change Address…") {
                        address = url
                        isChangingAddress = true
                    }
                    .disabled(!canEdit)
                }
                if server.plugin == nil, server.auth == "header" {
                    Button("Change API Key…") {
                        apiKey = ""
                        isChangingKey = true
                    }
                    .disabled(!canEdit)
                }
                if server.plugin == nil, bots.bots.contains(where: { $0.id != bot.id && $0.meta.hidden != true }) {
                    Button("Add to Other Bots…") { isAddingToBots = true }
                        .disabled(!canEdit)
                }
            }
            Section {
                HStack(spacing: 8) {
                    Button("Test Connection") { run { url, urlSession in await store.test(server.name, on: url, with: urlSession) } }
                        .disabled(!isOnline || !server.enabled || isBusy || status == .signingIn)
                    if isBusy {
                        Spacer(minLength: 8)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } footer: {
                if let failure = store.failures[server.id] {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
            #if os(macOS)
            if isSearchable {
                Section {
                    TextField(text: $query, prompt: Text("Search Tools")) {
                        Image(systemName: "magnifyingglass")
                    }
                    .multilineTextAlignment(.leading)
                }
            }
            #endif
            Section {
                toolRows(server, status: status, canEdit: canEdit)
            } header: {
                if case .connected(let count) = status {
                    Text("^[\(count) Tool](inflect: true)")
                } else {
                    Text("Tools")
                }
            } footer: {
                toolsFooter(server, status: status)
            }
            if server.plugin == nil {
                Section {
                    Button("Remove Connection…", role: .destructive) { isRemoving = true }
                        .disabled(!canEdit)
                }
            }
        }
        .formStyle(.grouped)
        .navigationDestination(isPresented: $isAddingToBots) {
            AddToBotsPage(bot: bot, server: server)
        }
        .alert("Change Address", isPresented: $isChangingAddress) {
            TextField("Address", text: $address)
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let address = address.trimmingCharacters(in: .whitespaces)
                run { url, urlSession in await store.changeAddress(address, for: server.name, on: url, with: urlSession) }
            }
            .disabled(!isNewAddress(for: server))
        } message: {
            Text("\(server.name) is tested again with the new address. Changes apply to new chats.")
        }
        .alert("Change API Key", isPresented: $isChangingKey) {
            SecureField("API Key", text: $apiKey)
            Button("Cancel", role: .cancel) { apiKey = "" }
            Button("Save") {
                let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                apiKey = ""
                guard let gateway = connection.gateway else { return }
                run { url, urlSession in await store.changeAPIKey(key, for: server.name, on: url, with: urlSession, gateway: gateway) }
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The old key is replaced. Changes apply to new chats.")
        }
        .confirmationDialog("Remove \(connectionLooks[server.name]?.title ?? server.name) from \(bot.title)?", isPresented: $isRemoving, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                run { url, urlSession in
                    await store.remove(server.name, on: url, with: urlSession)
                    if store.servers?.contains(where: { $0.name == server.name }) == false { dismiss() }
                }
            }
        } message: {
            Text("\(bot.title) loses these tools in new chats.")
        }
    }

    private func isNewAddress(for server: MCPServer) -> Bool {
        let parsed = URL(string: address.trimmingCharacters(in: .whitespaces))
        guard let scheme = parsed?.scheme?.lowercased(), ["https", "http"].contains(scheme), parsed?.host()?.isEmpty == false else { return false }
        return address.trimmingCharacters(in: .whitespaces) != server.url
    }

    @ViewBuilder
    private func toolRows(_ server: MCPServer, status: ConnectionStatus, canEdit: Bool) -> some View {
        if status == .off {
            Text("Turn on \(server.name) to see its tools.")
                .foregroundStyle(.secondary)
        } else if status == .checking {
            ProgressView()
                .controlSize(.small)
        } else if status == .signingIn {
            HStack(spacing: 8) {
                Text("Waiting for sign-in…")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Cancel") { run { url, urlSession in await store.cancelSignIn(server.name, on: url, with: urlSession) } }
                    .buttonStyle(.borderless)
            }
        } else if case .needsSignIn = status {
            HStack(spacing: 8) {
                Text("Sign in to see its tools.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Sign In") { signIn(server) }
                    .buttonStyle(.borderless)
                    .disabled(!isOnline || store.busy.contains(server.id))
            }
        } else if case .failed = status {
            Text("Tools appear when the connection works.")
                .foregroundStyle(.secondary)
        } else if tools.isEmpty {
            Text("This connection offers no tools.")
                .foregroundStyle(.secondary)
        } else {
            let matches = query.isEmpty ? tools : tools.filter { $0.name.localizedStandardContains(query) || ($0.description ?? "").localizedStandardContains(query) }
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            ForEach(matches, id: \.name) { tool in
                Toggle(isOn: Binding(get: { server.offers(tool.name) }, set: { value in run { url, urlSession in await store.setTool(tool.name, on: value, for: server.name, on: url, with: urlSession) } })) {
                    Text(tool.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let description = tool.description, !description.isEmpty {
                        Text(description)
                    }
                }
                .disabled(!canEdit || !server.canSwitch(tool.name))
            }
        }
    }

    @ViewBuilder
    private func toolsFooter(_ server: MCPServer, status: ConnectionStatus) -> some View {
        if case .connected = status {
            VStack(alignment: .leading, spacing: 4) {
                if let estimate = store.tests[server.id]?.tokenEstimate(for: server) {
                    Text("These tools use about \(estimate, format: .number) tokens of \(bot.title)'s context in every chat.")
                }
                if tools.contains(where: { !server.canSwitch($0.name) }) {
                    Text("Tools matched by a pattern in Hermes' config can't be switched here.")
                }
                Text("Changes apply to new chats.")
            }
        }
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
