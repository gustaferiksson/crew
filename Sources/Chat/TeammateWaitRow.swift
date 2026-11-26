import SwiftUI

struct TeammateWaitRow: View {
    let row: TeammateDelivery
    let teammate: Bot?
    let photo: Image?
    let now: Date
    let open: (Bot) -> Void
    let dismiss: () -> Void

    @ScaledMetric private var avatarSize: CGFloat = 20

    private var name: String { teammate?.title ?? row.targetHandle }

    private var tint: HierarchicalShapeStyle { row.state == .waitingOnYou ? .primary : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if let teammate {
                    BotAvatar(bot: teammate, status: nil, photo: photo, size: avatarSize)
                }
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.age(at: now))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Open") { if let teammate { open(teammate) } }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.borderless)
                    .disabled(teammate == nil)
                if row.state == .failed {
                    Button("Dismiss", systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 32)
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                        .help("Dismiss")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if row.state == .failed {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
                Text(row.status(for: name))
                    .foregroundStyle(row.state == .waitingOnYou ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .fontWeight(row.state == .waitingOnYou ? .medium : .regular)
                    .lineLimit(row.isUnknownOutcome ? nil : 2)
            }
            .font(.footnote)
            .padding(.leading, teammate == nil ? 0 : avatarSize + 8)
        }
        .help(row.preview)
        .contextMenu {
            if !row.preview.isEmpty { Text(row.preview) }
            if let error = row.error, !error.isEmpty { Text(error) }
            Button("Copy Message", systemImage: "doc.on.doc") {
                #if os(iOS)
                UIPasteboard.general.string = row.preview
                #else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.preview, forType: .string)
                #endif
            }
            if row.state == .failed { Button("Dismiss", systemImage: "xmark", action: dismiss) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(name), \(row.status(for: name)), \(row.age(at: now))"))
        .accessibilityValue(Text(row.preview))
    }
}
