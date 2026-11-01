import A2UICore
import A2UISwiftUI
import SwiftUI

extension EnvironmentValues {
    @Entry var pinKey: String?
    @Entry var openedCard: Binding<OpenedCard?>?
}

nonisolated let chatSpace = "chat"

struct OpenedCard: Equatable {
    let id: String
    let anchor: CGRect?
}

struct CardSummary {
    let title: String?
    let subtitle: String?
    let image: URL?
    let symbol: String
    let tint: Color

    init(_ root: Node?) {
        var queue = root.map { [$0] } ?? []
        var header: Node?
        var text: Node?
        while !queue.isEmpty, header == nil {
            let node = queue.removeFirst()
            if node.type == "Header" { header = node }
            if node.type == "Text", text == nil { text = node }
            queue += node.allChildNodes
        }
        let line = text?.string(for: "text")?.split(whereSeparator: \.isNewline).first.map { String(cardMarkdown(String($0)).characters) }
        title = [header?.string(for: "title"), line].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        subtitle = header?.string(for: "subtitle")?.trimmingCharacters(in: .whitespaces).split(whereSeparator: \.isNewline).first.map(String.init)
        image = header?.string(for: "image").flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        symbol = systemSymbol(header?.string(for: "symbol")) ?? "rectangle.on.rectangle"
        tint = crewTones[header?.string(for: "tone") ?? ""] ?? .accentColor
    }
}

struct PinnedCardButton: View {
    @ObservedObject var model: SurfaceViewModel
    let fallbackTitle: String
    let open: () -> Void
    let unpin: () -> Void

    var body: some View {
        let summary = CardSummary(model.rootNode)
        let title = summary.title ?? fallbackTitle
        Menu {
            Button("Unpin", systemImage: "pin.slash", action: unpin)
        } label: {
            Label(title, systemImage: summary.symbol)
        } primaryAction: {
            open()
        }
        .menuIndicator(.hidden)
        .help(title)
        .accessibilityHint("Shows the card")
        .accessibilityAction(named: "Unpin", unpin)
    }
}

struct PinnedCardContent: View {
    let surfaces: SurfaceStore
    let id: String
    let fallbackTitle: String
    let isPinned: Bool?
    let togglePin: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let model = surfaces.processor.surfaceGroupModel[id] {
            #if os(iOS)
            NavigationStack {
                card(model)
                    .navigationTitle(Text(CardSummary(model.rootNode).title ?? fallbackTitle))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) { dismiss() }
                        }
                        if let isPinned {
                            ToolbarItem(placement: .primaryAction) {
                                pinButton(isPinned)
                            }
                        }
                    }
            }
            .frame(idealWidth: 440, idealHeight: 560)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            #else
            VStack(alignment: .leading, spacing: 0) {
                if let isPinned {
                    HStack {
                        Spacer()
                        pinButton(isPinned)
                            .buttonStyle(.borderless)
                    }
                    .padding([.horizontal, .top], 12)
                }
                card(model)
            }
            .frame(width: 440)
            .frame(maxHeight: 560)
            #endif
        }
    }

    private func pinButton(_ isPinned: Bool) -> some View {
        Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin", action: togglePin)
    }

    private func card(_ model: SurfaceViewModel) -> some View {
        let content = Surface(viewModel: model, catalogs: crewCatalogs)
            .id(surfaces.owners[id])
            .environment(\.surfaceChoice, surfaces.choices[id])
            .disabled(surfaces.isBusy)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        #if os(macOS)
        return ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        #else
        return ScrollView { content }
        #endif
    }
}
