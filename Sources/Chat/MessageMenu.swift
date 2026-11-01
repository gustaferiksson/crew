import SwiftUI

extension EnvironmentValues {
    @Entry var messageSelection: Binding<Bool>?
    @Entry var transcriptTaps = 0
}

struct MessageMenu<PreviewShape: Shape>: ViewModifier {
    let text: String
    let shape: PreviewShape
    var remove: (() -> Void)?
    var speech: (id: String, profile: String?, name: String)?

    @State private var isSelecting = false
    @Environment(\.transcriptTaps) private var transcriptTaps

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .environment(\.messageSelection, $isSelecting)
            .onChange(of: transcriptTaps) { isSelecting = false }
            .task {
                guard Snapshot.requested == .chatSelection, text.contains("Merino") else { return }
                try? await Task.sleep(for: .seconds(1))
                isSelecting = true
            }
            .contentShape(.contextMenuPreview, shape)
            #endif
            .contextMenu {
                if !isSelecting {
                    Button("Copy", systemImage: "doc.on.doc") {
                        #if os(iOS)
                        UIPasteboard.general.string = text
                        #else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        #endif
                    }
                    #if os(iOS)
                    if !text.contains("<a2ui-json>") || markdownBlocks(from: a2uiFenced(text)).contains(where: { $0.kind != .code(language: "a2ui") }) {
                        Button("Select", systemImage: "selection.pin.in.out") { isSelecting = true }
                    }
                    #endif
                    ShareLink(item: text)
                    if let speech, !Speaker.shared.isRecording {
                        let spoken = BotAnswer.speech(from: text)
                        if Speaker.shared.speakingID == speech.id {
                            Button("Stop Speaking", systemImage: "stop.fill") { Speaker.shared.stop() }
                        } else if !spoken.isEmpty {
                            Button("Speak", systemImage: "speaker.wave.2") { Speaker.shared.speak(spoken, id: speech.id, profile: speech.profile, from: speech.name) }
                        }
                    }
                    if let remove {
                        Button("Remove from Queue", systemImage: "trash", role: .destructive, action: remove)
                    }
                }
            }
    }
}
