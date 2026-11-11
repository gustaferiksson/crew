import AppKit
import SwiftUI
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private struct DraftedChat: View {
    let transcript: Transcript
    let drafts: ChatDrafts

    var body: some View {
        ChatView(botName: "crew-test", avatar: EmptyView(), transcript: transcript, emptyState: EmptyView(), mentionable: [], draft: Binding(get: { drafts.text(for: crewTest.id) }, set: { drafts.update(crewTest.id, to: $0) }), tray: drafts.tray(for: crewTest.id))
    }
}

private final class KeyWindow: OffscreenWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor @Suite(.serialized) struct ComposerRedrawTests {
    private func textField(in view: NSView) -> NSTextField? {
        view as? NSTextField ?? view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    private func openChat(drafts: ChatDrafts) throws -> (KeyWindow, NSTextField) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let transcript = Transcript(history: try decoder.decode(HistoryFile.self, from: Data(contentsOf: fixtures.appending(path: "chat.long-replies.history.json"))).messages).visible
        let window = KeyWindow(size: NSSize(width: 700, height: 900), styleMask: [.titled, .resizable])
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: DraftedChat(transcript: transcript, drafts: drafts).environment(BotStore(fixture: [crewTest], statuses: [:])).environment(ChatPins(fileURL: nil)))
        window.setContentSize(NSSize(width: 700, height: 900))
        window.orderBack(nil)
        settle(1)
        return (window, try #require(window.contentView.flatMap { textField(in: $0) }))
    }

    @Test func focusingAndLeavingTheComposerLeaveTheChatAlone() throws {
        let drafts = ChatDrafts(fixture: [crewTest.id: "Already typed text"])
        let (window, field) = try openChat(drafts: drafts)
        defer { window.orderOut(nil) }

        chatViewBodies = 0
        #expect(window.makeFirstResponder(field))
        settle(0.5)
        let focusBodies = chatViewBodies

        chatViewBodies = 0
        #expect(window.makeFirstResponder(nil))
        settle(0.5)
        let blurBodies = chatViewBodies

        print("ComposerRedraw: \(focusBodies) ChatView bodies per focus, \(blurBodies) per blur")
        #expect(focusBodies == 0)
        #expect(blurBodies == 0)
        #expect(drafts.text(for: crewTest.id) == "Already typed text")
    }

    @Test func typingRedrawsOnlyTheComposer() throws {
        let drafts = ChatDrafts(fixture: [crewTest.id: "Book the"])
        let (window, field) = try openChat(drafts: drafts)
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(field))
        settle(0.5)
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.moveToEndOfDocument(nil)
        settle(0.5)

        chatViewBodies = 0
        let typed = " 07:10"
        for character in typed {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            settle(0.05)
        }
        settle(0.5)

        print("ComposerRedraw: \(chatViewBodies) ChatView bodies over \(typed.count) keystrokes")
        #expect(chatViewBodies == 0)
        #expect(drafts.text(for: crewTest.id) == "Book the 07:10")
    }
}
