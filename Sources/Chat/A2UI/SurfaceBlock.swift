import A2UICore
import A2UISwiftUI
import SwiftUI

extension EnvironmentValues {
    @Entry var surfaceChoice: String?
}

struct SurfaceBlock: View {
    let source: String

    @Environment(\.surfaces) private var store

    var body: some View {
        if let store, case .surfaces(let ids) = store.blocks[source] {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ids.filter { store.owners[$0] == source }, id: \.self) { id in
                    if let model = store.processor.surfaceGroupModel[id] {
                        SurfaceCard(model: model)
                            .environment(\.surfaceChoice, store.choices[id])
                            .disabled(store.isBusy)
                    }
                }
            }
        } else if let store, case .failed(let reason) = store.blocks[source] {
            FailedSurface(reason: reason, source: source)
        } else {
            Label {
                Text("Preparing card…")
            } icon: {
                ProgressView()
                    .controlSize(.small)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private struct SurfaceCard: View {
    @ObservedObject var model: SurfaceViewModel

    var body: some View {
        if let root = model.rootNode {
            Surface(viewModel: model, catalogs: crewCatalogs)
                .padding(root.type == "Card" ? 0 : 16)
                .background(.fill.quaternary.opacity(root.type == "Card" ? 0 : 1), in: .rect(cornerRadius: 20))
                .frame(maxWidth: 560, alignment: .leading)
        }
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
