import SwiftUI

struct TeammateWaitsCard: View {
    static let limit = 3

    let rows: [TeammateDelivery]
    let isStale: Bool
    let bots: [Bot]
    let photos: [Bot.ID: Image]
    let sender: String?
    let open: (Bot) -> Void
    let dismiss: (String) -> Void

    private var shown: [TeammateDelivery] { Array(rows.prefix(Self.limit)) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label("Waiting on teammates", systemImage: "person.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(shown) { row in
                        TeammateWaitRow(row: row, teammate: row.teammate(in: bots, sender: sender), photo: photos[row.target], now: context.date, open: open) { dismiss(row.id) }
                    }
                }
                .opacity(isStale ? 0.6 : 1)
                if rows.count > Self.limit {
                    Text("+\(rows.count - Self.limit) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if rows.contains(where: \.isUnknownOutcome) {
                    Text("Crew never resends a message.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if isStale {
                    Text("Couldn't refresh. Showing the last known state.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Waiting on teammates"))
        }
    }
}
