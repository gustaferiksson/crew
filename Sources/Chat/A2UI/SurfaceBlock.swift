import A2UICore
import A2UISwiftUI
import SwiftUI

extension EnvironmentValues {
    @Entry var surfaceChoice: String?
    @Entry var shownTurn: Binding<Turn.ID?>?
}

extension Transaction {
    static func cardUpdate(from old: [Turn.Status], to new: [Turn.Status], reducingMotion: Bool) -> Transaction {
        let hasFinished = zip(old.reversed(), new.reversed()).contains { $0 == .streaming && $1 != .streaming }
        guard hasFinished, !reducingMotion else { return Transaction() }
        return .disclosure(.smooth)
    }
}

struct SurfaceBlock: View {
    let source: String

    @Environment(\.surfaces) private var store
    @Environment(\.pinKey) private var pinKey
    #if os(iOS)
    @Environment(\.openedCard) private var openedCard
    #endif
    @Environment(\.expandedCards) private var expandedCards
    #if os(macOS)
    @Environment(\.cardWidths) private var cardWidths
    #endif
    @Environment(ChatPins.self) private var pins
    @State private var pinTaps = 0
    @State private var preview: SurfaceViewModel?

    var body: some View {
        if let store, case .surfaces(let created, let revised, let updated) = store.blocks[source] {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(created, id: \.self) { id in
                    if let model = store.processor.surfaceGroupModel[id] {
                        if store.owners[id] == source {
                            card(model, id: id, in: store, revised: revised.contains(id))
                        } else {
                            CardUpdateLine(model: model, id: id, direction: .below)
                        }
                    }
                }
                ForEach(updated, id: \.self) { id in
                    if store.present.contains(id), let model = store.processor.surfaceGroupModel[id] {
                        CardUpdateLine(model: model, id: id, direction: .above)
                    } else {
                        CardGoneLine()
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: pinTaps)
        } else if let store, store.blocks[source] == .lost {
            CardGoneLine()
        } else if let store, case .failed(let reason) = store.blocks[source] {
            FailedSurface(reason: reason, source: source)
        } else {
            CardPreview(model: preview ?? SurfaceViewModel(surfaceID: "", catalogs: [:]), fallbackTitle: String(localized: "Preparing card…")) { _ in }
                .disabled(true)
                .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: cardCorner)) }
                .frame(maxWidth: 560, alignment: .leading)
                .task(id: previewStep(forLength: source.utf8.count)) { refreshPreview() }
        }
    }

    private func card(_ model: SurfaceViewModel, id: String, in store: SurfaceStore, revised: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let expanded = expandedCards.map { cards in
                Binding { cards.wrappedValue.contains(id) } set: { if $0 { cards.wrappedValue.insert(id) } else { cards.wrappedValue.remove(id) } }
            }
            VStack(alignment: .leading, spacing: 0) {
                CardPreview(model: model, fallbackTitle: String(localized: "Card"), expanded: expanded) { frame in
                    #if os(iOS)
                    guard let openedCard else { return }
                    openedCard.wrappedValue = OpenedCard(id: id, anchor: openedCard.wrappedValue == nil ? frame : openedCard.wrappedValue?.anchor)
                    #else
                    withTransaction(.disclosure(.smooth)) { expanded?.wrappedValue.toggle() }
                    #endif
                }
                .contextMenu {
                    if let expanded {
                        Button(expanded.wrappedValue ? "Collapse Card" : "Expand Card", systemImage: expanded.wrappedValue ? "chevron.up" : "chevron.down") {
                            withAnimation(.smooth) { expanded.wrappedValue.toggle() }
                        }
                    }
                    if let pinKey {
                        let isPinned = pins.pinned(in: pinKey) == id
                        Button(isPinned ? "Unpin Card" : "Pin Card", systemImage: isPinned ? "pin.slash" : "pin") {
                            pinTaps += 1
                            pins.pin(isPinned ? nil : id, in: pinKey)
                        }
                    }
                }
                if expanded?.wrappedValue == true {
                    Surface(viewModel: model, catalogs: crewCatalogs)
                        .id(store.owners[id])
                        .environment(\.surfaceChoice, store.choices[id])
                        .environment(\.cardModel, model)
                        .environment(\.hiddenHeader, CardSummary(model.rootNode).header)
                        .disabled(store.isBusy)
                        .padding([.horizontal, .bottom], 20)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: cardCorner)) }
            #if os(macOS)
            .onPreferenceChange(TableWidth.self) { width in
                if width > 0 { cardWidths?.wrappedValue[id] = width }
            }
            .frame(maxWidth: expanded?.wrappedValue == true ? max(560, (cardWidths?.wrappedValue[id] ?? 0) + 40) : 560, alignment: .leading)
            #else
            .frame(maxWidth: 560, alignment: .leading)
            #endif
            if revised {
                Text("Updated")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
    }

    private func refreshPreview() {
        guard let store, store.isBusy, store.blocks[source] == nil, let model = store.preview(source) else { return }
        preview = model
    }
}

private struct CardUpdateLine: View {
    enum Direction {
        case above, below
    }

    @ObservedObject var model: SurfaceViewModel
    let id: String
    let direction: Direction

    @Environment(\.surfaces) private var store
    @Environment(\.shownTurn) private var shownTurn

    var body: some View {
        if direction == .below, let shownTurn, let turn = store?.cardTurns[id] {
            Button { shownTurn.wrappedValue = turn } label: {
                line
                    #if os(iOS)
                    .frame(minHeight: 44)
                    #endif
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the current version")
        } else {
            line
        }
    }

    private var line: some View {
        let title = CardSummary(model.rootNode).title ?? String(localized: "Card")
        return Label {
            if direction == .below {
                Text("\(title) · updated below")
            } else {
                Text("Updated \(title)")
            }
        } icon: {
            Image(systemName: direction == .below ? "arrow.down" : "arrow.up")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct CardGoneLine: View {
    var body: some View {
        Label("Updated a card that's no longer in this chat", systemImage: "rectangle.on.rectangle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct FailedSurface: View {
    let reason: String
    let source: String

    var body: some View {
        DisclosureGroup {
            ScrollView(.horizontal) {
                Text(source)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize()
            }
            .scrollIndicators(.hidden)
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label("Couldn't display this card", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fontWeight(.medium)
                Text(reason)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(.primary)
        .font(.footnote)
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
    }
}
