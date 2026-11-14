import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let context = extensionContext
        let inputs = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let restored = restoredURLSession()
        let sheet = ShareSheet(
            bots: VoiceBot.cached(),
            isSignedIn: restored != nil,
            load: { try await Self.items(in: inputs) },
            send: { message, attachments, bot in
                guard let (stored, urlSession) = restored else { throw HermesError.unauthorized }
                try await share(message, attachments: attachments, to: bot, on: stored.server, with: urlSession)
                context?.completeRequest(returningItems: nil)
            },
            cancel: { context?.cancelRequest(withError: CocoaError(.userCancelled)) }
        )
        let host = UIHostingController(rootView: sheet)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private nonisolated static func items(in inputs: [NSExtensionItem]) async throws -> [SharedItem] {
        var items: [SharedItem] = []
        for input in inputs {
            for provider in input.attachments ?? [] {
                guard let item = try await item(from: provider, title: input.attributedTitle?.string) else { continue }
                items.append(item)
            }
        }
        return items
    }

    private nonisolated static func item(from provider: NSItemProvider, title: String?) async throws -> SharedItem? {
        let name = provider.suggestedName ?? String(localized: "the shared item")
        guard let representation = SharedItem.representation(of: provider.registeredContentTypes) else { return nil }
        if case .file(let type) = representation {
            let attachment = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Attachment, any Error>) in
                _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                    guard let url else { return continuation.resume(throwing: AttachmentError.unreadable(name)) }
                    continuation.resume(with: Result { try Attachment(contentsOf: url) })
                }
            }
            return .file(attachment)
        }
        if representation == .url {
            let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(with: url.map { .success($0) } ?? .failure(AttachmentError.unreadable(name)))
                }
            }
            return url.isFileURL ? .file(try Attachment(contentsOf: url)) : .link(url, title: title)
        }
        let text = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(with: text.map { .success($0) } ?? .failure(AttachmentError.unreadable(name)))
            }
        }
        return .text(text)
    }
}
