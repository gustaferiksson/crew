import Foundation

nonisolated struct ProfileCapability: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let label: String?
    let description: String?
    let transport: String?
    let toolCount: Int?
    var enabled: Bool

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, label, description, transport, enabled
        case toolCount = "tool_count"
    }
}

nonisolated struct ModelChoice: Hashable, Sendable {
    let provider: String
    let model: String
}

nonisolated struct ProfileDetails: Decodable, Sendable {
    let name: String
    let description: String
    let soul: String
    let model: ModelChoice?
    let skills: [ProfileCapability]
    let mcpServers: [ProfileCapability]

    private enum CodingKeys: String, CodingKey {
        case name, description, soul, model, skills
        case mcpServers = "mcp_servers"
    }

    private enum ModelKeys: String, CodingKey {
        case provider
        case model = "default"
    }

    init(name: String, description: String, soul: String, model: ModelChoice?, skills: [ProfileCapability], mcpServers: [ProfileCapability]) {
        self.name = name
        self.description = description
        self.soul = soul
        self.model = model
        self.skills = skills
        self.mcpServers = mcpServers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        soul = try container.decodeIfPresent(String.self, forKey: .soul) ?? ""
        let model = try? container.nestedContainer(keyedBy: ModelKeys.self, forKey: .model)
        let provider = try model?.decodeIfPresent(String.self, forKey: .provider) ?? ""
        let identifier = try model?.decodeIfPresent(String.self, forKey: .model) ?? ""
        self.model = provider.isEmpty || identifier.isEmpty ? nil : ModelChoice(provider: provider, model: identifier)
        skills = try container.decodeIfPresent([ProfileCapability].self, forKey: .skills) ?? []
        mcpServers = try container.decodeIfPresent([ProfileCapability].self, forKey: .mcpServers) ?? []
    }
}

nonisolated struct ModelProvider: Decodable, Identifiable, Sendable {
    let slug: String
    let name: String
    let models: [String]

    var id: String { slug }
}

nonisolated struct ModelOptions: Decodable, Sendable {
    let providers: [ModelProvider]
    let model: String?
    let provider: String?

    var current: ModelChoice? {
        guard let model, let provider, !model.isEmpty, !provider.isEmpty else { return nil }
        return ModelChoice(provider: provider, model: model)
    }
}

nonisolated enum ModelConfirmation: Sendable {
    case ask, confirmed
}

nonisolated enum ModelChangeOutcome: Equatable, Sendable {
    case applied
    case needsConfirmation(String)
}

nonisolated struct ProfileError: LocalizedError {
    let errorDescription: String?
}

func changeModel(of profile: String, to choice: ModelChoice, confirmation: ModelConfirmation, via gateway: Gateway) async throws -> ModelChangeOutcome {
    var changes = ProfileChanges(name: profile)
    changes.model = choice.model
    changes.provider = choice.provider
    changes.confirmExpensiveModel = confirmation == .confirmed ? true : nil
    let reply = try await gateway.call("profiles.configure", changes, as: ConfigureReply.self)
    if reply.confirmRequired == true {
        return .needsConfirmation(reply.confirmMessage ?? String(localized: "This model may be expensive. Use it anyway?"))
    }
    guard reply.applied.model == true else { throw ProfileError(errorDescription: String(localized: "The server didn't change the model.")) }
    return .applied
}

nonisolated private struct ProfileConfig: Decodable {
    let agent: Agent?

    struct Agent: Decodable {
        let systemPrompt: JSONValue?
    }
}

nonisolated func instructions(of profile: String, on server: URL, with session: URLSession) async throws -> String {
    var request = hermesRequest("api/config", on: server)
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile), URLQueryItem(name: "include_defaults", value: "false")])
    let config = try await fetch(request, with: session, as: ProfileConfig.self)
    if case .string(let text) = config.agent?.systemPrompt { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard case .array(let lines) = config.agent?.systemPrompt else { return "" }
    return lines.compactMap { if case .string(let line) = $0 { line.trimmingCharacters(in: .whitespacesAndNewlines) } else { nil } }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}

nonisolated func saveInstructions(_ text: String, of profile: String, on server: URL, with session: URLSession) async throws {
    var request = hermesRequest("api/config", on: server)
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile)])
    request.httpMethod = "PUT"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["config": ["agent": ["system_prompt": text]]])
    _ = try await fetch(request, with: session, as: JSONValue.self)
}

nonisolated private struct ToolsetRow: Decodable {
    let name: String
    let label: String?
    let description: String?
    let enabled: Bool
    let tools: [String]?
}

nonisolated func toolsets(of profile: String, on server: URL, with session: URLSession) async throws -> [ProfileCapability] {
    var request = hermesRequest("api/tools/toolsets", on: server)
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile)])
    return try await fetch(request, with: session, as: [ToolsetRow].self).map {
        ProfileCapability(name: $0.name, label: $0.label, description: $0.description, transport: nil, toolCount: $0.tools?.count, enabled: $0.enabled)
    }
}

nonisolated func saveToolset(_ name: String, enabled: Bool, of profile: String, on server: URL, with session: URLSession) async throws {
    var request = hermesRequest("api/tools/toolsets/\(name)", on: server)
    request.url?.append(queryItems: [URLQueryItem(name: "profile", value: profile)])
    request.httpMethod = "PUT"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["enabled": enabled])
    _ = try await fetch(request, with: session, as: JSONValue.self)
}

nonisolated struct ProfileChanges: Encodable, Sendable {
    let name: String
    var uiMeta: [String: BotMeta]?
    var uiMetaExpectedRevisions: [String: Int]?
    var soul: String?
    var description: String?
    var model: String?
    var provider: String?
    var confirmExpensiveModel: Bool?
    var disabledSkills: [String]?
    var enabledMCPServers: [String]?

    private enum CodingKeys: String, CodingKey {
        case name, soul, description, model, provider
        case uiMeta = "ui_meta"
        case uiMetaExpectedRevisions = "ui_meta_expected_revisions"
        case confirmExpensiveModel = "confirm_expensive_model"
        case disabledSkills = "disabled_skills"
        case enabledMCPServers = "enabled_mcp_servers"
    }
}

nonisolated struct ConfigureReply: Decodable, Sendable {
    let applied: Applied
    let confirmRequired: Bool?
    let confirmMessage: String?

    struct Applied: Decodable, Sendable {
        let uiMeta: Bool?
        let uiMetaRevisions: [String: Int]?
        let uiMetaConflicts: JSONValue?
        let soul: Bool?
        let description: Bool?
        let model: Bool?
        let skills: Bool?
        let mcpServers: Bool?

        private enum CodingKeys: String, CodingKey {
            case soul, description, model, skills
            case uiMeta = "ui_meta"
            case uiMetaRevisions = "ui_meta_revisions"
            case uiMetaConflicts = "ui_meta_conflicts"
            case mcpServers = "mcp_servers"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case applied
        case confirmRequired = "confirm_required"
        case confirmMessage = "confirm_message"
    }
}

nonisolated struct AssetChange: Encodable, Sendable {
    let name: String
    let asset = "avatar"
    let data: String?
    let clear: Bool?
}

nonisolated struct AssetReply: Decodable, Sendable {
    let found: Bool?
    let ok: Bool?
    let data: String?
}

nonisolated struct ProfileRoster: Decodable, Sendable {
    let profiles: [Bot]
}
