import SwiftUI

nonisolated struct NewBotOptions: Equatable, Sendable {
    var model: ModelChoice?
    var copyKeys = true
    var bundledSkills = true
    var toolsets: [ProfileCapability] = []
    var loadedToolsets: [ProfileCapability] = []
    var connections: Set<String> = []

    var changedToolsets: [ProfileCapability] {
        toolsets.filter { toolset in loadedToolsets.first { $0.name == toolset.name }?.enabled != toolset.enabled }
    }

    func profile(name: String, description: String?, soul: String?, cloneFrom: String?) -> NewProfile {
        NewProfile(
            name: name, description: description, soul: soul, cloneFrom: cloneFrom,
            mirrorCredentials: copyKeys ? nil : false,
            noSkills: bundledSkills || cloneFrom != nil ? nil : true
        )
    }
}

struct NewBotAdvanced: View {
    @Binding var options: NewBotOptions
    let providers: [ModelProvider]
    let connections: [MCPServer]?
    let source: Bot?
    let defaultTitle: String

    var body: some View {
        Form {
            Section {
                Picker(selection: $options.model) {
                    Text(source.map { String(localized: "Same as \($0.title)") } ?? String(localized: "Server Default")).tag(nil as ModelChoice?)
                    ForEach(providers) { provider in
                        Section(provider.name) {
                            ForEach(provider.models, id: \.self) { model in
                                Text(model).tag(Optional(ModelChoice(provider: provider.slug, model: model)))
                            }
                        }
                    }
                } label: {
                    Label("Model", systemImage: "cpu")
                }
                Toggle(isOn: $options.copyKeys) {
                    Label("Copy API Keys", systemImage: "key")
                }
                if source == nil {
                    Toggle(isOn: $options.bundledSkills) {
                        Label("Bundled Skills", systemImage: "sparkles")
                    }
                }
            } footer: {
                Text(source == nil
                    ? "API keys and sign-ins come from \(defaultTitle). Without bundled skills the bot starts with none; turn single skills on later in its inspector."
                    : "API keys and sign-ins come from \(defaultTitle).")
            }
            Section {
                NavigationLink {
                    Form {
                        if options.toolsets.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                        ForEach($options.toolsets) { $toolset in
                            Toggle(isOn: $toolset.enabled) {
                                Text(toolset.label ?? toolset.name)
                                if let detail = toolset.description, !detail.isEmpty {
                                    Text(detail)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Toolsets")
                } label: {
                    LabeledContent {
                        Text("\(options.toolsets.filter(\.enabled).count) On")
                    } label: {
                        Label("Toolsets", systemImage: "wrench.and.screwdriver")
                    }
                }
            }
            if source == nil, let connections, !connections.isEmpty {
                Section {
                    ForEach(connections) { server in
                        Toggle(isOn: Binding(
                            get: { options.connections.contains(server.name) },
                            set: { isOn in
                                if isOn { options.connections.insert(server.name) } else { options.connections.remove(server.name) }
                            }
                        )) {
                            Text(server.name)
                            Text(server.address)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } header: {
                    Text("Connections")
                } footer: {
                    Text("Copies these connections from \(defaultTitle). Some need Copy API Keys or a new sign-in.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
    }
}

struct NewBotAdvancedFixture: View {
    @State private var options = NewBotOptions(
        model: ModelChoice(provider: "nous", model: "anthropic/claude-haiku-4.5"),
        toolsets: [
            ProfileCapability(name: "web", label: "Web Search & Scraping", description: "web_search, web_extract", transport: nil, toolCount: 2, enabled: true),
            ProfileCapability(name: "browser", label: "Browser Automation", description: "navigate, click, type, scroll", transport: nil, toolCount: 14, enabled: true),
            ProfileCapability(name: "terminal", label: "Terminal & Processes", description: "terminal, process", transport: nil, toolCount: 2, enabled: false),
        ],
        connections: ["files"]
    )

    var body: some View {
        NavigationStack {
            NewBotAdvanced(
                options: $options,
                providers: [
                    ModelProvider(slug: "openai-codex", name: "OpenAI Codex", models: ["gpt-6.1-sol", "gpt-6-luna"]),
                    ModelProvider(slug: "nous", name: "Nous Portal", models: ["anthropic/claude-haiku-4.5", "x-ai/grok-4.6"]),
                ],
                connections: [
                    MCPServer(name: "files", transport: "http", url: "http://host.containers.internal:8766/mcp", command: nil, args: [], auth: "header", enabled: true, source: "config", plugin: nil),
                    MCPServer(name: "icloud", transport: "http", url: "http://host.containers.internal:8767/mcp", command: nil, args: [], auth: "header", enabled: true, source: "config", plugin: nil),
                ],
                source: nil,
                defaultTitle: "Marlow"
            )
        }
    }
}
