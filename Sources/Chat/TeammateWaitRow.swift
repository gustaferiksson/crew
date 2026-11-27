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

    private var avatarBot: Bot {
        teammate ?? Bot(name: row.target, displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta(), metaRevision: nil)
    }

    private var tint: HierarchicalShapeStyle { row.state == .waitingOnYou ? .primary : .secondary }

    private var status: String { row.status(for: name) }

    private var line: AttributedString {
        var text = AttributedString(status)
        text.foregroundColor = row.state == .waitingOnYou ? Color.accentColor : Color.secondary
        guard let range = text.range(of: name) else {
            var lead = AttributedString("\(name) ")
            lead.font = .footnote.weight(.medium)
            return lead + text
        }
        text[range].font = .footnote.weight(.medium)
        text[range].foregroundColor = Color.primary
        return text
    }

    private var spokenLabel: String { status.contains(name) ? "\(status), \(row.age(at: now))" : "\(name), \(status), \(row.age(at: now))" }

    var body: some View {
        HStack(spacing: 8) {
            BotAvatar(bot: avatarBot, status: nil, photo: photo, size: avatarSize)
            if row.state == .failed {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
            Text(line)
                .font(.footnote)
                .lineLimit(row.isUnknownOutcome ? nil : 2)
            Spacer(minLength: 4)
            Text(row.age(at: now))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Open") { if let teammate { open(teammate) } }
                .font(.footnote.weight(.medium))
                .buttonStyle(.borderless)
                .padding(.horizontal, 4)
                .contentShape(.rect.inset(by: -14))
                .disabled(teammate == nil)
            if row.state == .failed {
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32)
                    .contentShape(.rect.inset(by: -6))
                    .buttonStyle(.plain)
                    .help("Dismiss")
            }
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
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityValue(Text(row.preview))
    }
}
