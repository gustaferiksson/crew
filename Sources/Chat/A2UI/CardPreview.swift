import A2UICore
import A2UISwiftUI
import SwiftUI

struct CardPreview: View {
    @ObservedObject var model: SurfaceViewModel
    let fallbackTitle: String
    let open: () -> Void

    @ScaledMetric private var tile: CGFloat = 44

    var body: some View {
        if model.rootNode != nil {
            preview(CardSummary(model.rootNode))
        }
    }

    private func preview(_ summary: CardSummary) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: summary.symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: tile, height: tile)
                    .background(summary.tint.gradient, in: .rect(cornerRadius: 12))
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
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 28)) }
        .frame(maxWidth: 560, alignment: .leading)
        .accessibilityLabel(summary.title ?? fallbackTitle)
        .accessibilityValue(summary.subtitle ?? String(localized: "Card"))
        .accessibilityHint("Shows the card")
    }
}
