import A2UICore
import A2UISwiftUI
import SwiftUI

extension EnvironmentValues {
    @Entry var pinKey: String?
}

struct CardSummary {
    let title: String?
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
        symbol = systemSymbol(header?.string(for: "symbol")) ?? "rectangle.on.rectangle"
        tint = crewTones[header?.string(for: "tone") ?? ""] ?? .accentColor
    }
}

struct PinnedCardBar: View {
    @ObservedObject var model: SurfaceViewModel
    let fallbackTitle: String
    let open: () -> Void
    let unpin: () -> Void

    @ScaledMetric private var tile: CGFloat = 28

    var body: some View {
        let summary = CardSummary(model.rootNode)
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: summary.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: tile, height: tile)
                        .background(summary.tint.gradient, in: .rect(cornerRadius: 8))
                        .accessibilityHidden(true)
                    Text(summary.title ?? fallbackTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 8)
                #if os(iOS)
                .frame(minHeight: 44)
                #else
                .frame(minHeight: 36)
                #endif
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue("Pinned card")
            .accessibilityHint("Shows the card")
            Button("Unpin", systemImage: "xmark", action: unpin)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
                #if os(iOS)
                .frame(width: 44, height: 44)
                #else
                .frame(width: 36, height: 36)
                #endif
                .contentShape(.rect)
        }
        .background { Color.clear.glassEffect(.regular.interactive(), in: .capsule) }
    }
}

struct PinnedCardContent: View {
    let surfaces: SurfaceStore
    let id: String
    let fallbackTitle: String
    let unpin: () -> Void

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
                        ToolbarItem(placement: .primaryAction) {
                            Button("Unpin", systemImage: "pin.slash", action: unpin)
                        }
                    }
            }
            .frame(idealWidth: 440, idealHeight: 560)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            #else
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button("Unpin", systemImage: "pin.slash", action: unpin)
                        .buttonStyle(.borderless)
                }
                .padding([.horizontal, .top], 12)
                card(model)
            }
            .frame(width: 440)
            .frame(maxHeight: 560)
            #endif
        }
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
