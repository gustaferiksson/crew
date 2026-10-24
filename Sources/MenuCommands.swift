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
        Button("New Group…") { open(.group) }
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

extension FocusedValues {
    @Entry var inspector: Binding<Bool>?
}
#endif
