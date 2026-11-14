import Foundation
import Observation

@Observable
final class PortraitGenerator {
    var description = ""
    private(set) var isAvailable: Bool
    private(set) var isGenerating: Bool
    private(set) var failure: String?
    private var generation: Task<Void, Never>?

    init(isAvailable: Bool = false, isGenerating: Bool = false, failure: String? = nil) {
        self.isAvailable = isAvailable
        self.isGenerating = isGenerating
        self.failure = failure
    }

    func probe(_ gateway: Gateway) async {
        let reply = try? await gateway.call("image.generate", ["probe": true], as: GeneratedImage.self)
        isAvailable = reply?.available == true
    }

    func generate(for draft: ProfileDraft, via gateway: Gateway) {
        cancel()
        isGenerating = true
        let prompt = Self.prompt(title: draft.title, description: draft.fields.description, custom: description)
        generation = Task {
            let generic = String(localized: "Crew couldn't generate a portrait. Check your connection and try again.")
            let failure: String?
            do {
                let reply = try await gateway.call("image.generate", ["prompt": prompt, "aspect_ratio": "square"], as: GeneratedImage.self, timeout: .seconds(90))
                let data = try await Self.image(from: reply)
                guard !Task.isCancelled else { return }
                failure = await draft.pickPhoto(data) ? nil : generic
            } catch GatewayError.rpc(_, let message) {
                failure = message
            } catch {
                failure = generic
            }
            guard !Task.isCancelled else { return }
            self.failure = failure
            isGenerating = false
            generation = nil
        }
    }

    func cancel() {
        generation?.cancel()
        generation = nil
        isGenerating = false
        failure = nil
    }

    nonisolated static func prompt(title: String, description: String, custom: String) -> String {
        let custom = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard custom.isEmpty else {
            return "\(custom). Avatar for an AI agent: centered, bold flat vector style, solid color background, no text."
        }
        let who = [title, description.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }.joined(separator: " — ")
        return "Cute minimal robot avatar for an AI agent named \"\(who)\". Friendly simple mascot face, bold flat vector style, solid color background, centered, no text."
    }

    nonisolated static func image(from reply: GeneratedImage, urlSession: URLSession = .shared) async throws -> Data {
        guard reply.success == true else {
            throw GatewayError.rpc(code: 0, message: reply.error ?? String(localized: "Crew couldn't generate a portrait. Check your connection and try again."))
        }
        if let url = reply.imageData, let comma = url.firstIndex(of: ","), let data = Data(base64Encoded: String(url[url.index(after: comma)...])) {
            return data
        }
        guard let image = reply.image, let url = URL(string: image), url.scheme == "https" else { throw URLError(.unsupportedURL) }
        let (data, response) = try await urlSession.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
