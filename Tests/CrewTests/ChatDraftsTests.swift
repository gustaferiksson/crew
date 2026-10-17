import Foundation
import Testing

@MainActor private func scratchFile() -> URL {
    URL.temporaryDirectory.appending(path: "crew-drafts-\(UUID().uuidString)/drafts.json")
}

@MainActor @Test func draftsSurviveARelaunch() {
    let file = scratchFile()
    let drafts = ChatDrafts(fileURL: file)
    drafts.update("scout", to: "Check the trains\nfrom Bodø too")
    drafts.update("group:r1", to: "Hi both")

    let relaunched = ChatDrafts(fileURL: file)
    #expect(relaunched.texts == ["scout": "Check the trains\nfrom Bodø too", "group:r1": "Hi both"])
    #expect(relaunched.preview(for: "scout") == "Check the trains from Bodø too")
}

@MainActor @Test func blankDraftsAreKeptWhileTypingButNeverStored() {
    let file = scratchFile()
    let drafts = ChatDrafts(fileURL: file)
    drafts.update("scout", to: "  ")
    #expect(drafts.texts["scout"] == "  ")
    #expect(drafts.preview(for: "scout") == nil)
    #expect(ChatDrafts(fileURL: file).texts.isEmpty)
}

@MainActor @Test func sendingAndDeletingClearTheDraft() {
    let file = scratchFile()
    let drafts = ChatDrafts(fileURL: file)
    drafts.update("scout", to: "Book it")
    drafts.update("forge", to: "Ship it")
    drafts.update("scout", to: "")
    drafts.clear("forge")
    #expect(drafts.texts.isEmpty)
    #expect(ChatDrafts(fileURL: file).texts.isEmpty)
}

@MainActor @Test func anAttachmentOnlyDraftPreviewsItsCount() {
    let drafts = ChatDrafts(fixture: [:])
    drafts.tray(for: "scout").items = [Attachment(kind: .file, name: "a.pdf"), Attachment(kind: .file, name: "b.pdf")]
    #expect(drafts.preview(for: "scout") == "2 Attachments")
    #expect(drafts.tray(for: "scout") === drafts.tray(for: "scout"))
}

@MainActor @Test func signingOutRemovesTheFile() {
    let file = scratchFile()
    let drafts = ChatDrafts(fileURL: file)
    drafts.update("scout", to: "Book it")
    drafts.reset()
    #expect(!FileManager.default.fileExists(atPath: file.path()))
    #expect(drafts.texts.isEmpty)
}
