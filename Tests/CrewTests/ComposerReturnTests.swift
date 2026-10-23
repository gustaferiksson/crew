import AppKit
import SwiftUI
import Testing

@MainActor @Observable private final class ReturnChat {
    var phase = Composer.Phase.idle
    var draft = ""
    var sends: [String] = []
}

private struct ReturnChatHost: View {
    let chat: ReturnChat
    @FocusState private var isFocused: Bool

    var body: some View {
        Composer(
            botName: "Marlow", phase: chat.phase, draft: Binding(get: { chat.draft }, set: { chat.draft = $0 }), isFocused: $isFocused,
            tray: AttachmentTray(), mentionable: [], completePath: { _ in [] }, transcribe: { _ in "" },
            send: { _ in
                chat.sends.append(chat.draft)
                chat.draft = ""
            },
            stop: {}
        )
    }
}

private final class KeyLoopWindow: NSWindow {
    var keyLoopRebuilds = 0
    var responderChanges = 0

    override func recalculateKeyViewLoop() {
        keyLoopRebuilds += 1
        super.recalculateKeyViewLoop()
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        responderChanges += 1
        return super.makeFirstResponder(responder)
    }
}

@MainActor struct ComposerReturnTests {
    private func settle() {
        RunLoop.main.run(until: .now + 0.5)
    }

    private func textField(in view: NSView) -> NSTextField? {
        view as? NSTextField ?? view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    private func press(_ window: NSWindow, shift: Bool = false, isARepeat: Bool = false) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: isARepeat, keyCode: 36
        ))
        window.sendEvent(event)
        settle()
    }

    private func focusedComposer(_ chat: ReturnChat) throws -> (KeyLoopWindow, NSTextView) {
        let window = KeyLoopWindow(contentRect: NSRect(x: -20000, y: -20000, width: 480, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ReturnChatHost(chat: chat))
        window.orderBack(nil)
        settle()
        let content = try #require(window.contentView)
        let field = try #require(textField(in: content))
        #expect(window.makeFirstResponder(field))
        return (window, try #require(window.firstResponder as? NSTextView))
    }

    @Test func returnNeverHandsTheKeyToTheFieldEditor() throws {
        let chat = ReturnChat()
        let (window, editor) = try focusedComposer(chat)
        defer { window.orderOut(nil) }
        editor.insertText("Summarise the plan", replacementRange: editor.selectedRange())
        settle()
        window.keyLoopRebuilds = 0
        window.responderChanges = 0

        try press(window)
        #expect(chat.sends == ["Summarise the plan"])
        #expect(window.responderChanges == 0, "Return with text")
        try press(window, isARepeat: true)
        #expect(window.responderChanges == 0, "held Return")
        #expect(chat.sends.count == 1, "held Return")
        try press(window)
        #expect(window.responderChanges == 0, "Return on the empty field")
        #expect(chat.sends.count == 1, "Return on the empty field")

        chat.phase = .offline(reason: "Can't reach hermes.example.com")
        editor.insertText("Then post it", replacementRange: editor.selectedRange())
        settle()
        try press(window)
        #expect(window.responderChanges == 0, "Return offline")
        #expect(chat.sends.count == 1, "Return offline")
        try press(window, shift: true)
        try press(window, shift: true, isARepeat: true)
        #expect(window.responderChanges == 0, "held Shift+Return")

        #expect(chat.sends == ["Summarise the plan"])
        #expect(chat.draft.hasPrefix("Then post it"))
        #expect(window.keyLoopRebuilds == 0)
        #expect(window.firstResponder === editor)
    }

    @Test func returnWhileComposingNeverSends() throws {
        let chat = ReturnChat()
        let (window, editor) = try focusedComposer(chat)
        defer { window.orderOut(nil) }
        editor.insertText("Hej ", replacementRange: editor.selectedRange())
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
        settle()

        try press(window)

        #expect(chat.sends.isEmpty)
    }
}
