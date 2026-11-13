#if os(iOS)
import SwiftUI

struct PinnedWidgetFixture: View {
    let empty: Bool

    private static let chef = VoiceBot(name: "chef", title: "Chef", session: nil, lastActive: nil, shape: "blob", color: "#f97316", expression: "happy", hidden: false)
    private static let groceries = PinnedWidgetContent.bot(chef, PinnedGlance(surface: "groceries", title: "Groceries for Saturday's dinner party", subtitle: nil, symbol: "cart", tone: "success", progress: .init(done: 2, total: 6)))
    private static let route = PinnedWidgetContent.bot(chef, PinnedGlance(surface: "route", title: "Coastal walk", subtitle: "12 km, 3 h 40 min", symbol: "figure.hiking", tone: "info", progress: nil))

    private var rows: [(content: PinnedWidgetContent, redacted: Bool)] {
        empty
            ? [(.noPins, false), (.missingBot, false), (.signedOut, false), (Self.groceries, true)]
            : [(Self.groceries, false), (Self.route, false), (.bot(Self.chef, nil), false), (.bot(Self.chef, PinnedGlance(surface: "big", title: "Camping", subtitle: nil, symbol: "tent", tone: "warning", progress: .init(done: 120, total: 150))), false)]
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    PinnedCardSmall(content: rows[index].content)
                        .padding(16)
                        .frame(width: 170, height: 170)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    VStack(alignment: .leading, spacing: 8) {
                        PinnedCardInline(content: rows[index].content)
                            .font(.subheadline)
                            .lineLimit(1)
                        PinnedCardRectangular(content: rows[index].content)
                            .frame(width: 172, height: 76)
                        PinnedCardCircular(content: rows[index].content)
                            .frame(width: 60, height: 60)
                    }
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(width: 190, height: 184, alignment: .topLeading)
                    .background(.indigo.gradient, in: .rect(cornerRadius: 24))
                    .environment(\.colorScheme, .dark)
                }
                .redacted(reason: rows[index].redacted ? .privacy : [])
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }
}
#endif
