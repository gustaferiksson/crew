import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private func reply(_ file: String) throws -> GeneratedImage {
    try JSONDecoder().decode(GeneratedImage.self, from: Data(contentsOf: fixtures.appending(path: file)))
}

private func contract(_ key: String) throws -> GeneratedImage {
    let replies = try JSONDecoder().decode([String: GeneratedImage].self, from: Data(contentsOf: fixtures.appending(path: "image.generate.success.contract.v0.23.1.json")))
    return try #require(replies[key])
}

private func draft() throws -> ProfileDraft {
    let roster = try JSONDecoder().decode(ProfileRoster.self, from: Data(contentsOf: fixtures.appending(path: "profiles.list.v0.21.7.json")))
    return ProfileDraft(bot: try #require(roster.profiles.first))
}

@Test func serverWithoutBackendHidesPortraits() throws {
    #expect(try reply("image.generate.probe.v0.23.1.json").available == false)
}

@Test func generateWithoutBackendShowsTheServersText() async throws {
    await #expect(throws: GatewayError.rpc(code: 0, message: "No image generation backend configured (run `hermes tools` to enable one).")) {
        try await PortraitGenerator.image(from: reply("image.generate.unavailable.v0.23.1.json"))
    }
    await #expect(throws: GatewayError.rpc(code: 0, message: "generation failed")) {
        try await PortraitGenerator.image(from: contract("failed"))
    }
}

@Test func inlineImageDataWinsAndSavesLikeAPhoto() async throws {
    let data = try await PortraitGenerator.image(from: contract("inline"))
    #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))

    let draft = try draft()
    #expect(await draft.pickPhoto(data))
    guard case .replace = draft.photoChange else {
        Issue.record("portrait not staged as a photo: \(draft.photoChange)")
        return
    }
    #expect(draft.outgoingMeta(draft.fields.identity).imageKind == "photo")
}

@Test func gatewayFilePathIsNotDownloadable() async throws {
    await #expect(throws: URLError.self) {
        try await PortraitGenerator.image(from: contract("gateway_path"))
    }
}

@Test func unreadableBytesAreRefusedWithoutThePhotoNotice() async throws {
    let draft = try draft()
    #expect(await draft.pickPhoto(Data("not an image".utf8)) == false)
    #expect(draft.notice == nil)
    #expect(draft.photoChange == .unchanged)
}

@Test func promptsMatchDesktop() {
    #expect(PortraitGenerator.prompt(title: "Ada", description: "Research assistant", custom: " ") ==
        "Cute minimal robot avatar for an AI agent named \"Ada — Research assistant\". Friendly simple mascot face, bold flat vector style, solid color background, centered, no text.")
    #expect(PortraitGenerator.prompt(title: "Ada", description: "", custom: "") ==
        "Cute minimal robot avatar for an AI agent named \"Ada\". Friendly simple mascot face, bold flat vector style, solid color background, centered, no text.")
    #expect(PortraitGenerator.prompt(title: "Ada", description: "Research assistant", custom: "An owl with glasses\n") ==
        "An owl with glasses. Avatar for an AI agent: centered, bold flat vector style, solid color background, no text.")
}

@Test func cancelDropsALateReply() async throws {
    let gateway = Gateway(server: URL(string: "https://hermes.example.com")!, urlSession: .shared) { "" }
    let kept = PortraitGenerator(isAvailable: true)
    let cancelled = PortraitGenerator(isAvailable: true)
    let draft = try draft()

    kept.generate(for: draft, via: gateway)
    cancelled.generate(for: draft, via: gateway)
    cancelled.cancel()
    for _ in 0..<50 where kept.isGenerating { try await Task.sleep(for: .milliseconds(20)) }

    #expect(kept.failure == "Crew couldn't generate a portrait. Check your connection and try again.")
    #expect(cancelled.failure == nil)
    #expect(!cancelled.isGenerating)
    #expect(draft.photoChange == .unchanged)
}
