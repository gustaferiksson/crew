import Foundation
import Testing
import UniformTypeIdentifiers

private let session = RuntimeSessionID(rawValue: "runtime-1")

@Test func sharedFilesWinOverTheirURLAndText() {
    #expect(SharedItem.representation(of: [.heic]) == .file(.heic))
    #expect(SharedItem.representation(of: [.fileURL, .pdf]) == .file(.pdf))
    #expect(SharedItem.representation(of: [.plainText, .png]) == .file(.png))
}

@Test func aSafariPageSendsItsURLNotItsText() {
    #expect(SharedItem.representation(of: [.url, .plainText]) == .url)
    #expect(SharedItem.representation(of: [.fileURL]) == .url)
    #expect(SharedItem.representation(of: [.plainText]) == .text)
    #expect(SharedItem.representation(of: [.utf8PlainText]) == .text)
    #expect(SharedItem.representation(of: []) == nil)
}

@Test func theMessageIsTheNoteThenEachLinkAndText() {
    let items: [SharedItem] = [
        .link(URL(string: "https://example.com/a")!, title: "A page"),
        .text("  Quoted paragraph.\n"),
        .file(Attachment(kind: .image, name: "photo.png", data: Data([1]))),
    ]
    #expect(SharedItem.message(note: " Read this ", items: items) == "Read this\n\nhttps://example.com/a\n\nQuoted paragraph.")
    #expect(SharedItem.message(note: "", items: [.text("Only text")]) == "Only text")
    #expect(SharedItem.message(note: "  ", items: [.file(Attachment(kind: .image, name: "photo.png", data: Data([1])))]).isEmpty)
}

@Test func sharesUseTheRoomLimits() throws {
    let large = SharedItem.file(Attachment(kind: .file, name: "Report.pdf", data: Data(count: 16 * 1_000_000)))
    let tooLarge = #expect(throws: AttachmentError.self) { try SharedItem.attachments(in: [large]) }
    #expect(tooLarge?.localizedDescription == "Report.pdf is larger than 15 MB.")
    let nine = (0..<9).map { SharedItem.file(Attachment(kind: .file, name: "\($0).txt", data: Data([1]))) }
    #expect(throws: AttachmentError.self) { try SharedItem.attachments(in: nine) }
    let fine: [SharedItem] = [.text("hi"), .file(Attachment(kind: .file, name: "a.txt", data: Data([1])))]
    #expect(try SharedItem.attachments(in: fine).map(\.name) == ["a.txt"])
}

@Test func imagesStageAsBytesAndFilesAsDataURLs() throws {
    let image = Attachment(kind: .image, name: "photo.png", data: Data([0x89, 0x50]))
    let pdf = Attachment(kind: .file, name: "Report.pdf", data: Data("%PDF".utf8))
    let staged = try #require(attachRequest(for: image, in: session))
    #expect(staged.method == "image.attach_bytes")
    #expect(staged.params == ["session_id": "runtime-1", "content_base64": "iVA=", "filename": "photo.png"])
    let attached = try #require(attachRequest(for: pdf, in: session))
    #expect(attached.method == "file.attach")
    #expect(attached.params == ["session_id": "runtime-1", "data_url": "data:application/pdf;base64,JVBERg==", "name": "Report.pdf"])
    #expect(attachRequest(for: Attachment(kind: .file, name: "remote.pdf", path: "/tmp/remote.pdf"), in: session) == nil)
}
