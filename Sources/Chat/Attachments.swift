import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct Attachment: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case image, file
    }

    struct Limits: Sendable {
        let file: Int
        let total: Int
        let megabyte: Int

        static let chat = Limits(file: 25, total: 50, megabyte: 1 << 20)
        static let room = Limits(file: 15, total: 25, megabyte: 1_000_000)
    }

    var id: String
    var kind: Kind
    var name: String
    var path: String?
    var data: Data?

    static let maxCount = 8
    private static let maxBytes = Limits.chat.file * Limits.chat.megabyte
    private static let maxPixels = 2048
    private static let passthroughTypes: Set<UTType> = [.png, .jpeg, .gif, .webP]

    var mimeType: String {
        UTType(filenameExtension: URL(filePath: name).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    init(kind: Kind, name: String, path: String? = nil, data: Data? = nil, id: String? = nil) {
        self.id = id ?? path ?? UUID().uuidString
        self.kind = kind
        self.name = name
        self.path = path
        self.data = data
    }

    init(data: Data, name: String) throws {
        guard !data.isEmpty else { throw AttachmentError.empty(name) }
        guard data.count <= Self.maxBytes else { throw AttachmentError.tooLarge(name, megabytes: Limits.chat.file) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier),
              type.conforms(to: .image),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            self.init(kind: .file, name: name, data: data)
            return
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? .max
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? .max
        let isUpright = (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1
        if Self.passthroughTypes.contains(type), max(width, height) <= Self.maxPixels, isUpright, data.count <= 5 << 20 {
            self.init(kind: .image, name: name, data: data)
            return
        }
        let output: UTType = type == .png ? .png : .jpeg
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixels,
        ] as CFDictionary
        let encoded = NSMutableData()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let destination = CGImageDestinationCreateWithData(encoded, output.identifier as CFString, 1, nil)
        else { throw AttachmentError.unreadable(name) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AttachmentError.unreadable(name) }
        let stem = URL(filePath: name).deletingPathExtension().lastPathComponent
        self.init(kind: .image, name: "\(stem).\(output.preferredFilenameExtension ?? "jpg")", data: encoded as Data)
    }

    init(contentsOf url: URL) throws {
        let name = url.lastPathComponent
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
        if values?.isDirectory == true || values?.isPackage == true { throw AttachmentError.folder(name) }
        if (values?.fileSize ?? 0) > Self.maxBytes { throw AttachmentError.tooLarge(name, megabytes: Limits.chat.file) }
        do {
            try self.init(data: Data(contentsOf: url), name: name)
        } catch let error as AttachmentError {
            throw error
        } catch {
            throw AttachmentError.unreadable(name)
        }
    }

    static func validated(_ attachments: [Attachment], limits: Limits = .chat) throws -> [Attachment] {
        guard attachments.count <= maxCount else { throw AttachmentError.tooMany }
        if let large = attachments.first(where: { ($0.data?.count ?? 0) > limits.file * limits.megabyte }) {
            throw AttachmentError.tooLarge(large.name, megabytes: limits.file)
        }
        guard attachments.reduce(0, { $0 + ($1.data?.count ?? 0) }) <= limits.total * limits.megabyte else { throw AttachmentError.tooLargeTotal(megabytes: limits.total) }
        return attachments
    }
}

nonisolated enum AttachmentError: LocalizedError {
    case empty(String)
    case tooLarge(String, megabytes: Int)
    case tooLargeTotal(megabytes: Int)
    case tooMany
    case folder(String)
    case unreadable(String)

    var errorDescription: String? {
        if case .empty(let name) = self { return String(localized: "\(name) is empty.") }
        if case .tooLarge(let name, let megabytes) = self { return String(localized: "\(name) is larger than \(megabytes) MB.") }
        if case .tooLargeTotal(let megabytes) = self { return String(localized: "Attachments can add up to \(megabytes) MB per message.") }
        if case .tooMany = self { return String(localized: "You can attach up to 8 files per message.") }
        if case .folder(let name) = self { return String(localized: "\(name) is a folder. Attach the files inside it instead.") }
        if case .unreadable(let name) = self { return String(localized: "Crew couldn't read \(name).") }
        return nil
    }
}

nonisolated let imageOnlyPrompt = "What do you see in this image?"
