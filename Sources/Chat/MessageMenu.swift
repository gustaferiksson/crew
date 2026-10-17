import SwiftUI

struct MessageMenu<PreviewShape: Shape>: ViewModifier {
    let text: String
    let shape: PreviewShape
    var remove: (() -> Void)?

    @State private var isSelecting = false

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .contentShape(.contextMenuPreview, shape)
            #endif
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    #if os(iOS)
                    UIPasteboard.general.string = text
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #endif
                }
                #if os(iOS)
                Button("Select", systemImage: "selection.pin.in.out") { isSelecting = true }
                #endif
                ShareLink(item: text)
                if let remove {
                    Button("Remove from Queue", systemImage: "trash", role: .destructive, action: remove)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $isSelecting) {
                SelectionSheet(text: text)
            }
            #endif
    }
}

#if os(iOS)
private struct SelectionSheet: View {
    let text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableText(text: text)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", role: .confirm) { dismiss() }
                    }
                }
        }
    }
}

private struct SelectableText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.text = text
    }
}
#endif
