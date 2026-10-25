import SwiftUI

private let reservedNames: Set<String> = [
    "hermes", "default", "test", "tmp", "root", "sudo",
    "chat", "model", "gateway", "setup", "whatsapp", "login", "logout", "status", "cron", "doctor", "dump", "config", "pairing",
    "skills", "tools", "mcp", "connectors", "sessions", "insights", "version", "update", "uninstall", "profile", "plugins", "honcho", "acp",
]

struct NewBotSheet: View {
    let onCreated: (Bot.ID) -> Void

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var title = ""
    @State private var role = ""
    @State private var description = ""
    @State private var instructions = ""
    @State private var source: Bot.ID?
    @State private var shape = AvatarShape.circle
    @State private var color = AvatarColor.adaptiveHex
    @State private var expression = AvatarExpression.neutral
    @State private var isCustom = false
    @State private var isCreating = false
    @State private var failure: String?
    @State private var options = NewBotOptions()
    @State private var providers: [ModelProvider] = []
    @State private var connections: [MCPServer]?
    @State private var created: Created?

    private struct Created {
        let name: String
        var expensiveModel: (choice: ModelChoice, message: String)?
        var unapplied: [String]
    }

    private var slug: String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil).lowercased()
        let dashed = String(folded.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "-" })
        return String(dashed.split(separator: "-").joined(separator: "-").prefix(64))
    }

    private var problem: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if slug.wholeMatch(of: /[a-z0-9][a-z0-9_-]{0,63}/) == nil { return String(localized: "Use at least one letter or number, and start with one.") }
        if reservedNames.contains(slug) { return String(localized: "“\(slug)” is reserved by Hermes. Pick another name.") }
        if store.bots.contains(where: { $0.name == slug }) { return String(localized: "A bot named “\(slug)” already exists.") }
        return nil
    }

    private var resolvedTitle: String? {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return named.isEmpty || named == slug ? nil : named
    }

    private var look: BotMeta {
        let role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return BotMeta(
            title: resolvedTitle,
            role: role.isEmpty ? nil : role,
            shape: isCustom ? shape.rawValue : nil,
            color: isCustom ? color : nil,
            custom: isCustom,
            imageKind: isCustom ? "shape" : nil,
            expression: expression == .neutral ? nil : expression.rawValue
        )
    }

    private var preview: Bot {
        Bot(
            name: slug.isEmpty ? "new-bot" : slug, displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false,
            canonicalSession: nil, meta: look, metaRevision: nil
        )
    }

    private var canCreate: Bool {
        !slug.isEmpty && problem == nil && !isCreating && connection.state == .connected
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        BotAvatar(bot: preview, status: .idle, photo: nil, size: 96)
                        Text(verbatim: resolvedTitle ?? (slug.isEmpty ? " " : slug))
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityHidden(resolvedTitle == nil && slug.isEmpty)
                        if let role = preview.role {
                            Text(role)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
                Section {
                    TextField("Name", text: $name, prompt: Text("Research Assistant"))
                        .autocorrectionDisabled()
                    TextField("Display Title", text: $title, prompt: Text(resolvedTitle ?? String(localized: "Display Title")))
                    TextField("Role", text: $role, prompt: Text("Role"))
                } header: {
                    Text("Name")
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else if !slug.isEmpty {
                        Text("Profile ID: \(slug)")
                    }
                }
                Section("Appearance") {
                    NavigationLink {
                        Form {
                            AvatarPicker(
                                shape: Binding(get: { shape }, set: { shape = $0; isCustom = true }),
                                color: Binding(get: { color }, set: { color = $0; isCustom = true }),
                                expression: $expression
                            ) {
                                shape = .circle
                                color = AvatarColor.adaptiveHex
                                expression = .neutral
                                isCustom = false
                            }
                        }
                        .formStyle(.grouped)
                        .navigationTitle("Appearance")
                    } label: {
                        Label {
                            Text("Avatar")
                        } icon: {
                            BotAvatar(bot: preview, status: .idle, photo: nil, size: 28)
                        }
                    }
                }
                Section {
                    Picker("Duplicate From", selection: $source) {
                        Text("None").tag(nil as Bot.ID?)
                        ForEach(store.bots) { bot in
                            Text(bot.title).tag(Optional(bot.id))
                        }
                    }
                } footer: {
                    Text(source == nil ? "Starts with the server's default model and bundled skills." : "Copies its model, skills, settings and instructions. Chats stay with the original.")
                }
                Section("Description") {
                    TextField("Description", text: $description, prompt: Text("What this bot is for"), axis: .vertical)
                        .lineLimit(2...4)
                        .labelsHidden()
                }
                Section {
                    TextEditor(text: $instructions)
                        .font(.body)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text(source == nil ? "Optional. Becomes the bot's SOUL.md." : "Optional. Replaces the copied instructions.")
                }
                Section {
                    NavigationLink("Advanced") {
                        NewBotAdvanced(
                            options: $options,
                            providers: providers,
                            connections: connections,
                            source: store.bots.first { $0.id == source },
                            defaultTitle: store.bots.first(where: \.isDefault)?.title ?? "default"
                        )
                    }
                } footer: {
                    Text("Model, API keys, skills, toolsets and connections.")
                }
            }
            .formStyle(.grouped)
            .disabled(isCreating)
            .navigationTitle("New Bot")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create", role: .confirm) { Task { await create() } }
                            .disabled(!canCreate)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCreating || created != nil)
        .task(id: source) { await loadOptions() }
        .alert(
            created?.expensiveModel == nil ? "Bot Created" : "Use This Model?",
            isPresented: Binding(get: { created != nil }, set: { _ in }),
            presenting: created
        ) { created in
            if let expensive = created.expensiveModel {
                Button("Use Anyway") { Task { await confirm(expensive.choice, for: created.name) } }
                Button("Keep Default", role: .cancel) { finish(created.name) }
            } else {
                Button("OK") { finish(created.name) }
            }
        } message: { created in
            let unapplied = created.unapplied.isEmpty ? nil : String(localized: "These options weren't applied: \(created.unapplied.formatted(.list(type: .and))). Change them in the bot's inspector.")
            Text([created.expensiveModel?.message, unapplied].compactMap { $0 }.joined(separator: "\n\n"))
        }
        #if os(macOS)
        .frame(minWidth: 440, idealHeight: 600)
        #endif
    }

    private func create() async {
        guard let gateway = connection.gateway, canCreate else { return }
        isCreating = true
        defer { isCreating = false }
        failure = nil
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = options.profile(
            name: slug,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            soul: instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : instructions,
            cloneFrom: source
        )
        let look = look
        do {
            try await store.create(profile, via: gateway) { $0 = look }
        } catch {
            failure = if case GatewayError.rpc(_, let message) = error { message } else { error.localizedDescription }
            return
        }
        let result = await apply(options, to: profile.name, via: gateway)
        if result.expensiveModel == nil && result.unapplied.isEmpty {
            finish(result.name)
        } else {
            created = result
        }
    }

    private func apply(_ options: NewBotOptions, to name: String, via gateway: Gateway) async -> Created {
        var result = Created(name: name, unapplied: [])
        do {
            for toolset in options.changedToolsets {
                try await saveToolset(toolset.name, enabled: toolset.enabled, of: name, on: gateway.server, with: connection.urlSession)
            }
        } catch {
            result.unapplied.append(String(localized: "toolsets"))
        }
        if source == nil && !options.connections.isEmpty {
            do {
                try await copyConnections(options.connections, from: "default", to: name, on: gateway.server, with: connection.urlSession)
            } catch {
                result.unapplied.append(String(localized: "connections"))
            }
        }
        guard let model = options.model else { return result }
        do {
            if case .needsConfirmation(let message) = try await changeModel(of: name, to: model, confirmation: .ask, via: gateway) {
                result.expensiveModel = (model, message)
            }
        } catch {
            result.unapplied.append(String(localized: "model"))
        }
        return result
    }

    private func confirm(_ model: ModelChoice, for name: String) async {
        if let gateway = connection.gateway {
            _ = try? await changeModel(of: name, to: model, confirmation: .confirmed, via: gateway)
        }
        finish(name)
    }

    private func finish(_ name: String) {
        created = nil
        onCreated(name)
        dismiss()
    }

    private func loadOptions() async {
        guard let gateway = connection.gateway else { return }
        let base = source ?? "default"
        let urlSession = connection.urlSession
        async let models = try? gateway.call("model.options", ["profile": base], as: ModelOptions.self).providers
        async let loadedToolsets = try? toolsets(of: base, on: gateway.server, with: urlSession)
        async let servers = try? fetch(mcpRequest("servers", profile: "default", on: gateway.server), with: urlSession, as: MCPServerList.self).servers
        let (loadedModels, toolsetList, serverList) = await (models, loadedToolsets, servers)
        providers = loadedModels ?? []
        options.model = nil
        options.toolsets = toolsetList ?? []
        options.loadedToolsets = toolsetList ?? []
        connections = serverList?.filter { $0.source == "config" }
    }
}

struct NewBotFixture: View {
    var body: some View {
        #if os(macOS)
        NewBotSheet { _ in }
        #else
        BotsView()
        #endif
    }
}
