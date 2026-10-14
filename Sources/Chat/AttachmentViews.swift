import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AttachmentTray {
    var items: [Attachment]
    var failure: String?

    init(items: [Attachment] = []) {
        self.items = items
    }

    func add(_ urls: [URL]) {
        Task {
            for url in urls {
                await append { try await loadAttachment(contentsOf: url) }
            }
        }
    }

    func add(_ photos: [PhotosPickerItem]) {
        Task {
            for photo in photos {
                await append {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw AttachmentError.unreadable(String(localized: "that photo")) }
                    return try await loadAttachment(data, name: "Photo.\(photo.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")")
                }
            }
        }
    }

    #if os(macOS)
    func paste() {
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { return add(urls) }
        guard let type = [NSPasteboard.PasteboardType.png, .tiff].first(where: { pasteboard.data(forType: $0) != nil }),
              let data = pasteboard.data(forType: type)
        else {
            failure = String(localized: "The clipboard has no image or file to attach.")
            return
        }
        Task {
            await append { try await loadAttachment(data, name: type == .png ? "Pasted Image.png" : "Pasted Image.tiff") }
        }
    }
    #endif

    func remove(_ id: Attachment.ID) {
        items.removeAll { $0.id == id }
    }

    func take() -> [Attachment] {
        defer { items = [] }
        return items
    }

    private func append(_ load: () async throws -> Attachment) async {
        do {
            items = try Attachment.validated(items + [try await load()])
        } catch {
            failure = error.localizedDescription
        }
    }
}

@concurrent
nonisolated private func loadAttachment(contentsOf url: URL) async throws -> Attachment {
    try Attachment(contentsOf: url)
}

@concurrent
nonisolated private func loadAttachment(_ data: Data, name: String) async throws -> Attachment {
    try Attachment(data: data, name: name)
}

@concurrent
nonisolated private func thumbnail(of data: Data, side: CGFloat) async -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: side * 3,
    ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
}

extension EnvironmentValues {
    @Entry var chatSession: ChatSession?
}

struct AttachmentThumbnail: View {
    let attachment: Attachment
    let side: CGFloat

    @Environment(\.chatSession) private var session
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.fill.tertiary)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityLabel(attachment.name)
        .task(id: attachment.id) {
            guard let data = try? await session?.download(attachment) ?? attachment.data else { return }
            image = await thumbnail(of: data, side: side)
        }
    }
}

struct FileChip: View {
    let attachment: Attachment

    var body: some View {
        Label {
            Text(attachment.name)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: attachment.name.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "doc")
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct PromptAttachments: View {
    let attachments: [Attachment]

    @Environment(\.chatSession) private var session
    @State private var preview: URL?
    @State private var failure: String?

    private var images: [Attachment] { attachments.filter { $0.kind == .image } }
    private var files: [Attachment] { attachments.filter { $0.kind == .file } }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if !images.isEmpty {
                ViewThatFits(in: .horizontal) {
                    imageRow
                    ScrollView(.horizontal) { imageRow }
                        .scrollIndicators(.hidden)
                        .defaultScrollAnchor(.trailing)
                }
            }
            ForEach(files) { file in
                Button { open(file) } label: {
                    FileChip(attachment: file)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
        .quickLookPreview($preview)
        .alert("Can't Open Attachment", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var imageRow: some View {
        HStack(spacing: 4) {
            ForEach(images) { image in
                Button { open(image) } label: {
                    AttachmentThumbnail(attachment: image, side: images.count == 1 ? 200 : 120)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func open(_ attachment: Attachment) {
        Task {
            do {
                let folder = URL.temporaryDirectory.appending(path: "Attachments/\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: attachment.name)
                guard let data = try await session?.download(attachment) ?? attachment.data else { throw HermesError.invalidResponse }
                try data.write(to: url)
                preview = url
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

struct PendingAttachments: View {
    let tray: AttachmentTray

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tray.items) { attachment in
                    Group {
                        if attachment.kind == .image {
                            AttachmentThumbnail(attachment: attachment, side: 64)
                        } else {
                            FileChip(attachment: attachment)
                                .padding(.trailing, 16)
                                .frame(height: 64)
                                .glassEffect(in: .rect(cornerRadius: 12))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button("Remove \(attachment.name)", systemImage: "xmark.circle.fill") {
                            withAnimation(.smooth) { tray.remove(attachment.id) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding(4)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
