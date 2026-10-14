import SwiftUI

extension Snapshot {
    static var profileDraft: ProfileDraft {
        let meta = BotMeta(title: "Ada", shape: "blob", color: "#8b5cf6", custom: true, imageKind: "shape", expression: "happy", pinned: true)
        let bot = Bot(
            name: "ada", displayName: nil, description: "Research assistant", model: "gpt-6-astra", isDefault: false, hasAvatar: false,
            canonicalSession: nil, meta: meta, metaRevision: 3
        )
        let skill = { (name: String, enabled: Bool) in
            ProfileCapability(name: name, label: nil, description: nil, transport: nil, toolCount: nil, enabled: enabled)
        }
        let toolset = { (name: String, label: String, tools: String, enabled: Bool) in
            ProfileCapability(name: name, label: label, description: tools, transport: nil, toolCount: nil, enabled: enabled)
        }
        let server = { (name: String, transport: String, enabled: Bool) in
            ProfileCapability(name: name, label: nil, description: nil, transport: transport, toolCount: nil, enabled: enabled)
        }
        let details = ProfileDetails(
            name: "ada",
            description: "Research assistant. Digs through papers, docs and the web, then writes up what it finds.",
            soul: """
            # Ada

            You are Ada, a careful research assistant.

            - Cite every source you use and link to it.
            - Prefer primary literature over blog posts.
            - Say plainly when the evidence is thin.
            - Summarise first, then go into detail.

            Keep answers short unless asked for depth.
            """,
            model: ModelChoice(provider: "openai-codex", model: "gpt-6-astra"),
            skills: [
                skill("arxiv", true), skill("ascii-art", false), skill("comfyui", false), skill("deep-research", true),
                skill("excalidraw", true), skill("github-pr-review", true), skill("google-workspace", false),
                skill("jupyter", true), skill("merge-reconciler", true), skill("notion", false), skill("obsidian", true),
                skill("plan", true), skill("webapp-testing", false), skill("youtube-transcripts", true),
            ],
            toolsets: [
                toolset("web", "🔍 Web Search & Scraping", "web_search, web_extract", true),
                toolset("browser", "🌐 Browser Automation", "navigate, click, type, scroll", true),
                toolset("terminal", "💻 Terminal & Processes", "terminal, process", true),
                toolset("file", "📁 File Operations", "read, write, patch, search", true),
                toolset("vision", "👁️ Vision / Image Analysis", "vision_analyze", false),
                toolset("image_gen", "🎨 Image Generation", "image_generate", false),
                toolset("memory", "🧠 Memory", "memory", true),
                toolset("delegation", "👥 Task Delegation", "delegate_task", true),
            ],
            mcpServers: [server("github", "stdio", true), server("linear", "http", false)]
        )
        return ProfileDraft(bot: bot, details: details, instructions: "Answer in British English and keep summaries under 200 words.")
    }

    static var profileModels: ModelSwitcher {
        ModelSwitcher(
            providers: [
                ModelProvider(slug: "openai-codex", name: "ChatGPT or Codex Subscription", models: ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-terra"]),
            ],
            current: ModelChoice(provider: "openai-codex", model: "gpt-6-astra")
        )
    }
}

struct ProfileSkillsFixture: View {
    @State private var items = Snapshot.profileDraft.fields.skills

    var body: some View {
        #if os(macOS)
        CapabilityList(kind: .skills, items: $items)
        #else
        InspectorFixtureScreen(tab: .info)
            .sheet(isPresented: .constant(true)) {
                CapabilityList(kind: .skills, items: $items)
            }
        #endif
    }
}

struct LookFixture: View {
    @State private var draft = Snapshot.profileDraft

    var body: some View {
        #if os(macOS)
        LookEditor(draft: draft, photoItem: .constant(nil))
        #else
        InspectorFixtureScreen(tab: .info)
            .sheet(isPresented: .constant(true)) {
                LookEditor(draft: draft, photoItem: .constant(nil))
            }
        #endif
    }
}
