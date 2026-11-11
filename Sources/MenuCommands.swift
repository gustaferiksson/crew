#if os(macOS)
import SwiftUI

struct NewChatCommands: View {
    let connection: Connection
    let groups: GroupStore
    let scenes: Scenes
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Bot…") { open(.bot) }
            .keyboardShortcut("n")
            .disabled(connection.state != .connected)
        Button("New Room…") { open(.group) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(connection.state != .connected || !groups.isSupported)
    }

    private func open(_ kind: Scenes.NewChat) {
        scenes.newChat = kind
        openWindow(id: "main")
    }
}

struct InspectorCommand: View {
    @FocusedBinding(\.inspector) private var isPresented

    var body: some View {
        Button(isPresented == true ? "Hide Inspector" : "Show Inspector") {
            isPresented?.toggle()
        }
        .keyboardShortcut("i", modifiers: [.control, .command])
        .disabled(isPresented == nil)
    }
}

struct PinnedCardCommand: View {
    @FocusedBinding(\.pinnedCard) private var isPresented

    var body: some View {
        Button(isPresented == true ? "Hide Pinned Card" : "Show Pinned Card") { isPresented?.toggle() }
            .disabled(isPresented == nil)
    }
}

extension FocusedValues {
    @Entry var inspector: Binding<Bool>?
    @Entry var pinnedCard: Binding<Bool>?
}
#endif
