#if os(iOS)
import ImageIO
import SwiftUI

struct ShareSheet: View {
    let bots: [VoiceBot]
    let isSignedIn: Bool
    let load: () async throws -> [SharedItem]
    let send: (_ message: String, _ attachments: [Attachment], _ bot: VoiceBot) async throws -> Void
    let cancel: () -> Void

    @State private var items: [SharedItem]?
    @State private var attachments: [Attachment] = []
    @State private var problem: String?
    @State private var failure: String?
    @State private var note = ""
    @State private var botName: String
    @State private var isSending = false
    @FocusState private var isNoteFocused: Bool

    init(bots: [VoiceBot], isSignedIn: Bool, load: @escaping () async throws -> [SharedItem], send: @escaping (String, [Attachment], VoiceBot) async throws -> Void, cancel: @escaping () -> Void) {
        self.bots = bots
        self.isSignedIn = isSignedIn
        self.load = load
        self.send = send
        self.cancel = cancel
        _botName = State(initialValue: VoiceBot.choose(nil, from: bots)?.name ?? "")
    }

    private var listed: [VoiceBot] {
        bots.filter { !$0.hidden }.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    private var message: String {
        SharedItem.message(note: note, items: items ?? [])
    }

    private var canSend: Bool {
        items != nil && problem == nil && !isSending && listed.contains { $0.name == botName } && (!message.isEmpty || !attachments.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isSignedIn {
                    ContentUnavailableView("Sign in to Crew", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("Open Crew and sign in, then share again."))
                } else if listed.isEmpty {
                    ContentUnavailableView("No Bots", systemImage: "bubble.left.and.bubble.right", description: Text("Open Crew to load your bots."))
                } else {
                    compose
                }
            }
            .navigationTitle("Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: cancel)
                }
                if isSignedIn && !listed.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending {
                            ProgressView()
                        } else {
                            Button("Send", role: .confirm) { Task { await sendItems() } }
                                .disabled(!canSend)
                        }
                    }
                }
            }
        }
        .task { await loadItems() }
    }

    private var compose: some View {
        Form {
            Section {
                Picker("To", selection: $botName) {
                    ForEach(listed, id: \.name) { bot in
                        Label {
                            Text(bot.title)
                        } icon: {
                            VoiceAvatar(bot: bot, size: 28)
                        }
                        .tag(bot.name)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Section {
                TextField("Add a note", text: $note, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isNoteFocused)
            } footer: {
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
            Section {
                if let items {
                    ForEach(items.indices, id: \.self) { index in
                        SharedItemRow(item: items[index])
                    }
                } else if problem == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                if let problem {
                    Text(problem)
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(isSending)
        .onAppear { isNoteFocused = true }
    }

    private func loadItems() async {
        do {
            let loaded = try await load()
            items = loaded
            attachments = try SharedItem.attachments(in: loaded)
        } catch {
            problem = error.localizedDescription
        }
    }

    private func sendItems() async {
        guard canSend, let bot = listed.first(where: { $0.name == botName }) else { return }
        isSending = true
        failure = nil
        do {
            try await send(message, attachments, bot)
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn't send. Check your connection and try again.")
            isSending = false
        }
    }
}

private struct SharedItemRow: View {
    let item: SharedItem

    var body: some View {
        switch item {
        case .text(let text):
            Text(text)
                .lineLimit(4)
        case .link(let url, let title):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? url.host() ?? url.absoluteString)
                        .font(.headline)
                        .lineLimit(2)
                    Text(url.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } icon: {
                Image(systemName: "link")
            }
        case .file(let attachment):
            HStack(spacing: 12) {
                if attachment.kind == .image, let image = thumbnail(of: attachment) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "doc")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, height: 60)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text((attachment.data?.count ?? 0).formatted(.byteCount(style: .file)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func thumbnail(of attachment: Attachment) -> CGImage? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 180] as CFDictionary
        guard let data = attachment.data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
#endif
