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

    @State private var showsAll = false

    private var shown: [TeammateDelivery] { showsAll ? rows : Array(rows.prefix(Self.limit)) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shown) { row in
                        TeammateWaitRow(row: row, teammate: row.teammate(in: bots, sender: sender), photo: photos[row.target], now: context.date, open: open) { dismiss(row.id) }
                    }
                }
                .opacity(isStale ? 0.6 : 1)
                if rows.count > Self.limit {
                    Button(showsAll ? "Show Less" : "+\(rows.count - Self.limit) more") { showsAll.toggle() }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                        .accessibilityValue(showsAll ? Text("Expanded") : Text("Collapsed"))
                }
                if isStale {
                    Text("Couldn't refresh. Showing the last known state.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Waiting on teammates"))
        }
    }
}
