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
        .interactiveDismissDisabled(isCreating)
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
        let profile = NewProfile(
            name: slug,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            soul: instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : instructions,
            cloneFrom: source
        )
        let look = look
        do {
            try await store.create(profile, via: gateway) { $0 = look }
            onCreated(profile.name)
            dismiss()
        } catch {
            failure = if case GatewayError.rpc(_, let message) = error { message } else { error.localizedDescription }
        }
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
