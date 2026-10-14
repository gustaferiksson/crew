import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct Attachment: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case image, file
    }

    var id: String
    var kind: Kind
    var name: String
    var path: String?
    var data: Data?

    static let maxBytes = 25 << 20
    static let maxCount = 8
    static let maxTotalBytes = 50 << 20
    private static let maxPixels = 2048
    private static let passthroughTypes: Set<UTType> = [.png, .jpeg, .gif, .webP]

    var mimeType: String {
        UTType(filenameExtension: URL(filePath: name).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    init(kind: Kind, name: String, path: String? = nil, data: Data? = nil) {
        self.id = path ?? UUID().uuidString
        self.kind = kind
        self.name = name
        self.path = path
        self.data = data
    }

    init(data: Data, name: String) throws {
        guard !data.isEmpty else { throw AttachmentError.empty(name) }
        guard data.count <= Self.maxBytes else { throw AttachmentError.tooLarge(name) }
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
        if (values?.fileSize ?? 0) > Self.maxBytes { throw AttachmentError.tooLarge(name) }
        do {
            try self.init(data: Data(contentsOf: url), name: name)
        } catch let error as AttachmentError {
            throw error
        } catch {
            throw AttachmentError.unreadable(name)
        }
    }

    static func validated(_ attachments: [Attachment]) throws -> [Attachment] {
        guard attachments.count <= maxCount else { throw AttachmentError.tooMany }
        guard attachments.reduce(0, { $0 + ($1.data?.count ?? 0) }) <= maxTotalBytes else { throw AttachmentError.tooLargeTotal }
        return attachments
    }
}

nonisolated enum AttachmentError: LocalizedError {
    case empty(String)
    case tooLarge(String)
    case tooLargeTotal
    case tooMany
    case folder(String)
    case unreadable(String)

    var errorDescription: String? {
        if case .empty(let name) = self { return String(localized: "\(name) is empty.") }
        if case .tooLarge(let name) = self { return String(localized: "\(name) is larger than 25 MB.") }
        if case .tooLargeTotal = self { return String(localized: "Attachments can add up to 50 MB per message.") }
        if case .tooMany = self { return String(localized: "You can attach up to 8 files per message.") }
        if case .folder(let name) = self { return String(localized: "\(name) is a folder. Attach the files inside it instead.") }
        if case .unreadable(let name) = self { return String(localized: "Crew couldn't read \(name).") }
        return nil
    }
}

extension Prompt {
    nonisolated init(raw: String, sentAt: Date) {
        var lines = raw.components(separatedBy: "\n")
        var attachments: [Attachment] = []
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty || last == "[image]" || last == "[screenshot]" {
            lines.removeLast()
        }
        while let last = lines.last, let path = Self.reference(last, prefix: "@image:") {
            attachments.insert(Attachment(kind: .image, name: URL(filePath: path).lastPathComponent, path: path), at: 0)
            lines.removeLast()
        }
        while let first = lines.first, let path = Self.reference(first, prefix: "@file:") {
            attachments.append(Attachment(kind: .file, name: URL(filePath: path).lastPathComponent, path: path))
            lines.removeFirst()
        }
        let body = lines.joined(separator: "\n")
        let text = ["\n\n--- Context Warnings ---", "\n\n--- Attached Context ---"]
            .compactMap { body.range(of: $0)?.lowerBound }
            .min()
            .map { String(body[..<$0]) }
            ?? body
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hidesCaption = trimmed == imageOnlyPrompt && attachments.contains { $0.kind == .image }
        self.init(text: hidesCaption ? "" : trimmed, sentAt: sentAt, attachments: attachments)
    }

    private nonisolated static func reference(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let quote = value.first, "`\"'".contains(quote), value.count > 1, value.last == quote else {
            return value.isEmpty || value.contains(" ") ? nil : value
        }
        return String(value.dropFirst().dropLast())
    }
}

nonisolated let imageOnlyPrompt = "What do you see in this image?"
