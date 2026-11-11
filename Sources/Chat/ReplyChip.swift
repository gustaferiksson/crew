import SwiftUI

struct ReplyChip: View {
    let reply: ReplyTarget
    let cancel: () -> Void

    #if os(iOS)
    @ScaledMetric private var height: CGFloat = 36
    #else
    @ScaledMetric private var height: CGFloat = 30
    #endif

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Replying to \(reply.name)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                if !reply.quote.isEmpty {
                    Text(reply.quote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reply.quote.isEmpty ? Text("Replying to \(reply.name)") : Text("Replying to \(reply.name), \(reply.quote)"))
            .accessibilityAction(named: "Cancel Reply", cancel)
            Button("Cancel Reply", systemImage: "xmark", action: cancel)
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: height - 4, height: height)
                .contentShape(.rect)
                .help("Cancel Reply")
        }
        .frame(minHeight: height)
        .buttonStyle(.plain)
        .background { Color.clear.glassEffect(.regular, in: .capsule) }
    }
}
