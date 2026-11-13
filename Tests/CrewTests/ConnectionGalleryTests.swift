import Foundation
import Testing

struct ConnectionGalleryTests {
    private let catalog: [MCPCatalogEntry] = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/mcp/catalog.v0.23.1.json")
        return (try? decoder.decode(MCPCatalog.self, from: Data(contentsOf: url)).entries) ?? []
    }()

    private func server(_ name: String) -> MCPServer {
        MCPServer(name: name, transport: "http", url: nil, command: nil, args: [], auth: nil, enabled: true, source: "config", plugin: nil)
    }

    @Test func theOverlayNamesEveryEntryOfTheRecordedCatalog() {
        #expect(catalog.count == 66)
        #expect(catalog.filter { connectionLooks[$0.name] == nil }.map(\.name) == [])
        let sections = gallerySections(catalog: catalog, servers: [], query: "")
        #expect(sections.map(\.category) == [.productivity, .developer, .data, .business, .design, .reference, .travel])
        #expect(sections.flatMap(\.entries).count == 69)
        #expect(sections.first { $0.category == .reference }?.entries.map(\.name) == ["aws-knowledge", "context7", "deepwiki", "microsoft-learn", "twilio-docs", "wolfram"])
    }

    @Test func everyOverlaySymbolExists() {
        #expect(connectionLooks.values.filter { systemSymbol($0.symbol) == nil }.map(\.symbol) == [])
    }

    @Test func anUnknownNameShowsRawUnderOther() throws {
        let unknown = MCPCatalogEntry(name: "acme-notes", description: "Notes from Acme.", transport: "http", authType: "oauth", requiredEnv: [], command: nil, args: [], url: "https://mcp.acme.example/mcp", postInstall: "", installed: false)
        let sections = gallerySections(catalog: catalog + [unknown], servers: [], query: "")
        #expect(sections.last?.category == .other)
        #expect(sections.last?.entries.map(\.name) == ["acme-notes"])
        #expect(gallerySections(catalog: [unknown], servers: [], query: "acme").map(\.category) == [.other])
    }

    @Test func extrasShowAddedFromTheServerListAndYieldToTheCatalog() throws {
        let sections = gallerySections(catalog: catalog, servers: [server("zapier")], query: "")
        let all = sections.flatMap(\.entries)
        #expect(all.filter(\.installed).map(\.name) == ["zapier"])
        #expect(all.first { $0.name == "github" }?.url == "https://api.githubcopilot.com/mcp/")

        let hermesGitHub = MCPCatalogEntry(name: "github", description: "From Hermes.", transport: "http", authType: "oauth", requiredEnv: [], command: nil, args: [], url: "https://hermes.example/github", postInstall: "", installed: false)
        let merged = gallerySections(catalog: [hermesGitHub], servers: [], query: "").flatMap(\.entries)
        #expect(merged.filter { $0.name == "github" }.map(\.description) == ["From Hermes."])
    }

    @Test func searchMatchesDisplayNameRawNameDescriptionAndCategory() {
        let names = { (query: String) in gallerySections(catalog: self.catalog, servers: [], query: query).flatMap(\.entries).map(\.name) }
        #expect(names("Hugging Face") == ["hugging_face"])
        #expect(names("n8n-official") == ["n8n-official"])
        #expect(names("hotel") == ["trivago"])
        #expect(names("travel") == ["alltrails", "kiwi", "strava", "trivago"])
        #expect(names("no such thing").isEmpty)
    }
}
