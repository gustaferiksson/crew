import Foundation

nonisolated enum ConnectionCategory: String, CaseIterable, Sendable {
    case productivity = "Productivity"
    case developer = "Developer Tools"
    case data = "Data & Monitoring"
    case business = "Business & Finance"
    case design = "Design & Media"
    case reference = "Reference"
    case travel = "Travel & Lifestyle"
    case other = "Other"
}

nonisolated struct ConnectionLook: Equatable, Sendable {
    let title: String
    let category: ConnectionCategory
    let symbol: String
    var tokenPage: URL? = nil
}

nonisolated let connectionLooks: [String: ConnectionLook] = [
    "airtable": ConnectionLook(title: "Airtable", category: .productivity, symbol: "tablecells"),
    "algolia": ConnectionLook(title: "Algolia", category: .developer, symbol: "magnifyingglass"),
    "alltrails": ConnectionLook(title: "AllTrails", category: .travel, symbol: "figure.hiking"),
    "amplitude": ConnectionLook(title: "Amplitude", category: .data, symbol: "chart.bar"),
    "asana": ConnectionLook(title: "Asana", category: .productivity, symbol: "checklist"),
    "atlassian": ConnectionLook(title: "Atlassian", category: .productivity, symbol: "rectangle.stack"),
    "attio": ConnectionLook(title: "Attio", category: .business, symbol: "person.crop.rectangle.stack"),
    "aws-knowledge": ConnectionLook(title: "AWS Knowledge", category: .reference, symbol: "books.vertical"),
    "betterstack": ConnectionLook(title: "Better Stack", category: .data, symbol: "waveform.path.ecg"),
    "buildkite": ConnectionLook(title: "Buildkite", category: .developer, symbol: "hammer"),
    "calendly": ConnectionLook(title: "Calendly", category: .productivity, symbol: "calendar.badge.clock"),
    "canva": ConnectionLook(title: "Canva", category: .design, symbol: "paintpalette"),
    "circleci": ConnectionLook(title: "CircleCI", category: .developer, symbol: "arrow.triangle.2.circlepath"),
    "clickup": ConnectionLook(title: "ClickUp", category: .productivity, symbol: "checkmark.circle"),
    "close": ConnectionLook(title: "Close", category: .business, symbol: "phone"),
    "cloudflare": ConnectionLook(title: "Cloudflare", category: .developer, symbol: "cloud"),
    "cloudinary": ConnectionLook(title: "Cloudinary", category: .design, symbol: "photo.on.rectangle"),
    "comfy-cloud": ConnectionLook(title: "Comfy Cloud", category: .design, symbol: "wand.and.stars"),
    "context7": ConnectionLook(title: "Context7", category: .reference, symbol: "book"),
    "craft": ConnectionLook(title: "Craft", category: .productivity, symbol: "doc.richtext"),
    "datadog": ConnectionLook(title: "Datadog", category: .data, symbol: "chart.xyaxis.line"),
    "deepwiki": ConnectionLook(title: "DeepWiki", category: .reference, symbol: "book.closed"),
    "dropbox": ConnectionLook(title: "Dropbox", category: .productivity, symbol: "folder"),
    "figma": ConnectionLook(title: "Figma", category: .design, symbol: "pencil.and.ruler"),
    "fireflies": ConnectionLook(title: "Fireflies", category: .productivity, symbol: "waveform"),
    "gamma": ConnectionLook(title: "Gamma", category: .design, symbol: "play.rectangle"),
    "github": ConnectionLook(title: "GitHub", category: .developer, symbol: "chevron.left.forwardslash.chevron.right", tokenPage: URL(string: "https://github.com/settings/personal-access-tokens/new")),
    "gitlab": ConnectionLook(title: "GitLab", category: .developer, symbol: "arrow.triangle.branch"),
    "globalping": ConnectionLook(title: "Globalping", category: .developer, symbol: "network"),
    "grafana": ConnectionLook(title: "Grafana", category: .data, symbol: "gauge.with.dots.needle.33percent"),
    "granola": ConnectionLook(title: "Granola", category: .productivity, symbol: "note.text"),
    "hugging_face": ConnectionLook(title: "Hugging Face", category: .developer, symbol: "face.smiling"),
    "indeed": ConnectionLook(title: "Indeed", category: .business, symbol: "briefcase"),
    "intercom": ConnectionLook(title: "Intercom", category: .business, symbol: "bubble.left.and.bubble.right"),
    "kiwi": ConnectionLook(title: "Kiwi.com", category: .travel, symbol: "airplane"),
    "klaviyo": ConnectionLook(title: "Klaviyo", category: .business, symbol: "envelope"),
    "linear": ConnectionLook(title: "Linear", category: .productivity, symbol: "list.bullet.rectangle"),
    "microsoft-learn": ConnectionLook(title: "Microsoft Learn", category: .reference, symbol: "graduationcap"),
    "miro": ConnectionLook(title: "Miro", category: .productivity, symbol: "scribble.variable"),
    "mixpanel": ConnectionLook(title: "Mixpanel", category: .data, symbol: "chart.pie"),
    "monday": ConnectionLook(title: "monday.com", category: .productivity, symbol: "rectangle.split.3x1"),
    "motherduck": ConnectionLook(title: "MotherDuck", category: .data, symbol: "bird"),
    "n8n-official": ConnectionLook(title: "n8n", category: .productivity, symbol: "point.3.filled.connected.trianglepath.dotted"),
    "neon": ConnectionLook(title: "Neon", category: .developer, symbol: "cylinder.split.1x2"),
    "netlify": ConnectionLook(title: "Netlify", category: .developer, symbol: "globe"),
    "notion": ConnectionLook(title: "Notion", category: .productivity, symbol: "doc.text"),
    "paypal": ConnectionLook(title: "PayPal", category: .business, symbol: "dollarsign.circle"),
    "plaid": ConnectionLook(title: "Plaid", category: .business, symbol: "building.columns"),
    "postman": ConnectionLook(title: "Postman", category: .developer, symbol: "paperplane"),
    "prisma-postgres": ConnectionLook(title: "Prisma Postgres", category: .developer, symbol: "cylinder"),
    "railway": ConnectionLook(title: "Railway", category: .developer, symbol: "tram"),
    "rentahuman": ConnectionLook(title: "RentAHuman", category: .business, symbol: "person.2"),
    "robinhood": ConnectionLook(title: "Robinhood", category: .business, symbol: "banknote"),
    "semgrep": ConnectionLook(title: "Semgrep", category: .developer, symbol: "lock.shield"),
    "sentry": ConnectionLook(title: "Sentry", category: .developer, symbol: "ant"),
    "square": ConnectionLook(title: "Square", category: .business, symbol: "cart"),
    "strava": ConnectionLook(title: "Strava", category: .travel, symbol: "figure.run"),
    "stripe": ConnectionLook(title: "Stripe", category: .business, symbol: "creditcard"),
    "supabase": ConnectionLook(title: "Supabase", category: .developer, symbol: "server.rack"),
    "todoist": ConnectionLook(title: "Todoist", category: .productivity, symbol: "checkmark.square"),
    "trivago": ConnectionLook(title: "trivago", category: .travel, symbol: "bed.double"),
    "twelve-data": ConnectionLook(title: "Twelve Data", category: .data, symbol: "chart.line.uptrend.xyaxis"),
    "twilio-docs": ConnectionLook(title: "Twilio Docs", category: .reference, symbol: "doc.text.magnifyingglass"),
    "unreal-engine": ConnectionLook(title: "Unreal Engine", category: .developer, symbol: "gamecontroller"),
    "vercel": ConnectionLook(title: "Vercel", category: .developer, symbol: "triangle"),
    "webflow": ConnectionLook(title: "Webflow", category: .design, symbol: "rectangle.3.group"),
    "wolfram": ConnectionLook(title: "Wolfram", category: .reference, symbol: "function"),
    "wordpress-com": ConnectionLook(title: "WordPress.com", category: .design, symbol: "newspaper"),
    "zapier": ConnectionLook(title: "Zapier", category: .productivity, symbol: "bolt"),
]

nonisolated let connectionExtras = [
    MCPCatalogEntry(name: "github", description: "Repositories, issues, and pull requests on GitHub.", transport: "http", authType: "header", requiredEnv: [], command: nil, args: [], url: "https://api.githubcopilot.com/mcp/", postInstall: "", installed: false),
    MCPCatalogEntry(name: "granola", description: "Meeting notes and transcripts from Granola.", transport: "http", authType: "oauth", requiredEnv: [], command: nil, args: [], url: "https://mcp.granola.ai/mcp", postInstall: "", installed: false),
    MCPCatalogEntry(name: "zapier", description: "Actions in thousands of apps through your Zapier account.", transport: "http", authType: "oauth", requiredEnv: [], command: nil, args: [], url: "https://mcp.zapier.com/api/v1/connect", postInstall: "", installed: false),
]

nonisolated func gallerySections(catalog: [MCPCatalogEntry], servers: [MCPServer], query: String) -> [(category: ConnectionCategory, entries: [MCPCatalogEntry])] {
    let extras = connectionExtras.filter { extra in !catalog.contains { $0.name == extra.name } }.map { extra in
        var extra = extra
        extra.installed = servers.contains { $0.name == extra.name }
        return extra
    }
    let title = { (entry: MCPCatalogEntry) in connectionLooks[entry.name]?.title ?? entry.name }
    let matches = (catalog + extras).filter { entry in
        query.isEmpty || [title(entry), entry.name, entry.description, (connectionLooks[entry.name]?.category ?? .other).rawValue].contains { $0.localizedStandardContains(query) }
    }
    let grouped = Dictionary(grouping: matches) { connectionLooks[$0.name]?.category ?? .other }

    return ConnectionCategory.allCases.compactMap { category in
        grouped[category].map { (category, $0.sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }) }
    }
}
