import AppKit
import SwiftUI
import Testing

@MainActor @Observable private final class RunningChat {
    var phase = Composer.Phase.running
    let drafts = ChatDrafts(fixture: [:])
}

private struct RunningChatHost: View {
    let chat: RunningChat
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            if chat.phase == .idle {
                ReplySegmentText(text: NSAttributedString(string: "Deployed to staging."), source: "Deployed to staging.", offset: 0)
            }
            Composer(
                botName: "Hermes", phase: chat.phase, draft: Binding(get: { chat.drafts.texts["ada", default: ""] }, set: { chat.drafts.update("ada", to: $0) }), isFocused: $isFocused,
                tray: AttachmentTray(), mentionable: [], completePath: { _ in [] }, transcribe: { _ in "" }, send: { _ in }, stop: {}
            )
        }
    }
}

@MainActor struct ComposerCaretTests {
    private func settle() {
        RunLoop.main.run(until: .now + 0.5)
    }

    private func textField(in view: NSView) -> NSTextField? {
        view as? NSTextField ?? view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    @Test func theCaretStaysPutWhenTheFinishedReplyArrives() throws {
        let chat = RunningChat()
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 480, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: RunningChatHost(chat: chat))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle()
        let content = try #require(window.contentView)
        let field = try #require(textField(in: content))
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSTextView)
        for character in "Use the staging context" {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
        editor.setSelectedRange(NSRange(location: 16, length: 0))
        settle()

        chat.phase = .idle
        settle()

        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange() == NSRange(location: 16, length: 0))
        editor.insertText("X", replacementRange: editor.selectedRange())
        settle()
        #expect(chat.drafts.texts["ada"] == "Use the staging Xcontext")
    }
}
