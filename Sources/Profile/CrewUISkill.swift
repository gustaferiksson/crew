import Foundation

nonisolated let crewUISkillName = "crew-ui"

nonisolated let crewUISkill = Bundle.main.url(forResource: "crew-ui.SKILL", withExtension: "md").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

nonisolated func crewUISkillVersion(_ content: String) -> Int {
    content.firstMatch(of: /\nversion: *(\d+) *\n/).flatMap { Int($0.1) } ?? 0
}

nonisolated private struct SkillContent: Decodable {
    let content: String
}

nonisolated func installCrewUISkill(in profile: String, on server: URL, with session: URLSession) async throws {
    var lookup = hermesRequest("api/skills/content", on: server)
    lookup.url?.append(queryItems: [URLQueryItem(name: "name", value: crewUISkillName), URLQueryItem(name: "profile", value: profile)])
    let installed: SkillContent?
    do {
        installed = try await fetch(lookup, with: session, as: SkillContent.self)
    } catch HermesError.server(let code) where code == 404 {
        installed = nil
    }
    if let installed, crewUISkillVersion(installed.content) >= crewUISkillVersion(crewUISkill) { return }
    var request = hermesRequest(installed == nil ? "api/skills" : "api/skills/content", on: server, json: ["name": crewUISkillName, "content": crewUISkill, "profile": profile])
    if installed != nil { request.httpMethod = "PUT" }
    _ = try await fetch(request, with: session, as: JSONValue.self)
}
