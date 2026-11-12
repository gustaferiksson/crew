import A2UICore
import A2UISwiftUI
import SwiftUI

#if os(iOS)
let cardCorner: CGFloat = 28
private let tileCorner: CGFloat = 12
private let previewPadding: CGFloat = 12
#else
let cardCorner: CGFloat = 18
private let tileCorner: CGFloat = 8
private let previewPadding: CGFloat = 10
#endif

struct CardPreview: View {
    @ObservedObject var model: SurfaceViewModel
    let fallbackTitle: String
    var expanded: Binding<Bool>?
    let open: (CGRect) -> Void

    #if os(iOS)
    @ScaledMetric private var tile: CGFloat = 44
    @ScaledMetric private var chevronTarget: CGFloat = 44
    #else
    @ScaledMetric private var tile: CGFloat = 32
    #endif
    @State private var frame = CGRect.zero

    var body: some View {
        preview(CardSummary(model.rootNode))
            .redacted(reason: model.rootNode == nil ? .placeholder : [])
    }

    private func preview(_ summary: CardSummary) -> some View {
        HStack(spacing: 0) {
            openButton(summary)
            #if os(iOS)
            if let expanded {
                Button(expanded.wrappedValue ? "Collapse" : "Expand", systemImage: "chevron.down") {
                    withTransaction(.disclosure(.smooth)) { expanded.wrappedValue.toggle() }
                }
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
                .buttonStyle(.borderless)
                .frame(width: chevronTarget, height: chevronTarget)
                .contentShape(.rect)
                .accessibilityValue(summary.title ?? fallbackTitle)
                .padding(.trailing, 4)
            }
            #endif
        }
    }

    private func openButton(_ summary: CardSummary) -> some View {
        Button { open(frame) } label: {
            HStack(spacing: 12) {
                Image(systemName: summary.symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: tile, height: tile)
                    .background(summary.tint.gradient, in: .rect(cornerRadius: tileCorner))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title ?? fallbackTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if let subtitle = summary.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let image = summary.image {
                    CachedImage(url: image) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.fill.tertiary)
                        }
                    }
                    .frame(width: tile, height: tile)
                    .clipShape(.rect(cornerRadius: tileCorner))
                    .accessibilityHidden(true)
                }
                #if os(macOS)
                if let expanded {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
                        .accessibilityHidden(true)
                }
                #endif
            }
            .padding(previewPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary.title ?? fallbackTitle)
        .accessibilityValue(summary.subtitle ?? String(localized: "Card"))
        #if os(iOS)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(chatSpace)) } action: { frame = $0 }
        .accessibilityHint("Shows the card")
        .accessibilityActions {
            if let expanded {
                Button(expanded.wrappedValue ? "Collapse Card" : "Expand Card") { expanded.wrappedValue.toggle() }
            }
        }
        #else
        .accessibilityHint(expanded?.wrappedValue == true ? "Collapses the card" : "Expands the card")
        #endif
    }
}
