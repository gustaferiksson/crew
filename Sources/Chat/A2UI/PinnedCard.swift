import A2UICore
import A2UISwiftUI
import SwiftUI

extension EnvironmentValues {
    @Entry var pinKey: String?
    #if os(iOS)
    @Entry var openedCard: Binding<OpenedCard?>?
    #endif
    @Entry var expandedCards: Binding<Set<String>>?
    @Entry var hiddenHeader: String?
}

nonisolated let chatSpace = "chat"

struct OpenedCard: Equatable {
    let id: String
    let anchor: CGRect?
}

struct CardSummary {
    let header: String?
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
        self.header = header?.id
        title = [header?.string(for: "title"), line].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        subtitle = header?.string(for: "subtitle")?.trimmingCharacters(in: .whitespaces).split(whereSeparator: \.isNewline).first.map(String.init)
        image = header?.string(for: "image").flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        symbol = systemSymbol(header?.string(for: "symbol")) ?? "rectangle.on.rectangle"
        tint = crewTones[header?.string(for: "tone") ?? ""] ?? .accentColor
    }
}

struct PinnedCardChip: View {
    @ObservedObject var model: SurfaceViewModel
    let fallbackTitle: String
    let open: () -> Void
    let unpin: () -> Void

    @ScaledMetric private var tile: CGFloat = 24
    #if os(iOS)
    @ScaledMetric private var height: CGFloat = 36
    #else
    @ScaledMetric private var height: CGFloat = 30
    #endif

    var body: some View {
        let summary = CardSummary(model.rootNode)
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: summary.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: tile, height: tile)
                        .background(summary.tint.gradient, in: .circle)
                        .accessibilityHidden(true)
                    Text(summary.title ?? fallbackTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.leading, (height - tile) / 2)
                .padding(.trailing, 4)
                .frame(minHeight: height)
                .contentShape(.rect)
            }
            .help(summary.title ?? fallbackTitle)
            .accessibilityValue("Pinned card")
            .accessibilityHint("Shows the card")
            .accessibilityAction(named: "Unpin", unpin)
            Button("Unpin", systemImage: "xmark", action: unpin)
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: height - 4, height: height)
                .contentShape(.rect)
                .help("Unpin")
        }
        .buttonStyle(.plain)
        .background { Color.clear.glassEffect(.regular.interactive(), in: .capsule) }
        .contentShape(.capsule)
        .contextMenu { Button("Unpin", systemImage: "pin.slash", action: unpin) }
    }
}

struct PinnedCardContent: View {
    let surfaces: SurfaceStore
    let id: String
    let fallbackTitle: String
    let isPinned: Bool?
    let togglePin: () -> Void

    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @State private var tableWidth: CGFloat = 0
    #endif

    var body: some View {
        #if os(iOS)
        if let model = surfaces.processor.surfaceGroupModel[id] {
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
        }
        #else
        if let model = surfaces.processor.surfaceGroupModel[id] {
            card(model)
                .onPreferenceChange(TableWidth.self) { tableWidth = $0 }
                .frame(width: min(max(440, tableWidth + 40), 800))
                .frame(maxHeight: 640)
                .fixedSize(horizontal: false, vertical: true)
                .toolbar {
                    if let isPinned {
                        ToolbarItem(placement: .destructiveAction) {
                            pinButton(isPinned)
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private func pinButton(_ isPinned: Bool) -> some View {
        Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin", action: togglePin)
    }

    private func card(_ model: SurfaceViewModel) -> some View {
        ScrollView {
            Surface(viewModel: model, catalogs: crewCatalogs)
                .id(surfaces.owners[id])
                .environment(\.surfaceChoice, surfaces.choices[id])
                .disabled(surfaces.isBusy)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
